// Minimal stand-in for the Android SDK's apksigner, implementing APK
// Signature Scheme v2 with nothing but the JDK.
//
// Why this exists: Godot's Android export shells out to `apksigner` to sign
// the APK it has just built, and refuses to export without it. The Android
// SDK is not always available (and on a locked-down build machine cannot
// always be fetched), so this covers the two sub-commands Godot actually
// uses, `sign` and `verify`.
//
// Scheme v2 alone is enough here because the Godot 4.7 Android template
// declares minSdkVersion 24: every device that can run the game is Android
// 7.0 or newer, and those all understand v2. Apps that need to reach Android
// 5 or 6 would also need the older JAR signing scheme, which this does not do.
//
// Format reference: https://source.android.com/docs/security/features/apksigning/v2
//
//   build:  javac -d out ApkSignerV2.java
//   sign:   java -cp out ApkSignerV2 sign --ks k.jks --ks-pass pass:x \
//                  --ks-key-alias a --key-pass pass:x app.apk
//   verify: java -cp out ApkSignerV2 verify app.apk

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.file.Files;
import java.security.KeyStore;
import java.security.MessageDigest;
import java.security.PrivateKey;
import java.security.Signature;
import java.security.cert.X509Certificate;
import java.util.ArrayList;
import java.util.List;

public final class ApkSignerV2 {

	private static final byte[] MAGIC = "APK Sig Block 42".getBytes(java.nio.charset.StandardCharsets.US_ASCII);
	private static final int V2_BLOCK_ID = 0x7109871a;
	/** RSASSA-PKCS1-v1_5 over SHA2-256, digesting with SHA2-256. */
	private static final int SIG_ALGO_RSA_SHA256 = 0x0103;
	private static final int CHUNK_SIZE = 1024 * 1024;
	private static final int EOCD_SIGNATURE = 0x06054b50;

	public static void main(String[] args) {
		try {
			if (args.length == 0) {
				usage();
				System.exit(1);
			}
			switch (args[0]) {
				case "sign" -> sign(args);
				case "verify" -> verify(args);
				case "version", "--version" -> System.out.println("0.9 (ApkSignerV2, JDK only)");
				default -> {
					usage();
					System.exit(1);
				}
			}
		} catch (Throwable error) {
			System.err.println("apksigner: " + error);
			System.exit(1);
		}
	}

	private static void usage() {
		System.err.println("usage: apksigner sign --ks <keystore> --ks-pass pass:<pw> "
				+ "--ks-key-alias <alias> --key-pass pass:<pw> [--out <apk>] <apk>");
		System.err.println("       apksigner verify [--verbose] <apk>");
	}

	// --- command line -------------------------------------------------------

	/** Godot passes flags apksigner understands; anything unknown is skipped. */
	private static String option(String[] args, String name) {
		for (int i = 0; i < args.length - 1; i++) {
			if (args[i].equals(name)) {
				return args[i + 1];
			}
		}
		return null;
	}

	private static String lastFile(String[] args) {
		String found = null;
		for (int i = 1; i < args.length; i++) {
			String a = args[i];
			if (a.startsWith("-")) {
				// Skip this flag's value when it takes one.
				if (takesValue(a) && i + 1 < args.length) {
					i++;
				}
				continue;
			}
			found = a;
		}
		return found;
	}

	private static boolean takesValue(String flag) {
		return switch (flag) {
			case "--ks", "--ks-pass", "--ks-key-alias", "--key-pass", "--out", "--ks-type",
					"--ks-provider-name", "--ks-provider-class", "--ks-provider-arg",
					"--min-sdk-version", "--max-sdk-version", "--key", "--cert" -> true;
			default -> false;
		};
	}

	private static char[] password(String spec) throws Exception {
		if (spec == null) {
			return new char[0];
		}
		if (spec.startsWith("pass:")) {
			return spec.substring(5).toCharArray();
		}
		if (spec.startsWith("file:")) {
			return Files.readString(new File(spec.substring(5)).toPath()).trim().toCharArray();
		}
		if (spec.startsWith("env:")) {
			String value = System.getenv(spec.substring(4));
			return value == null ? new char[0] : value.toCharArray();
		}
		return spec.toCharArray();
	}

	// --- signing ------------------------------------------------------------

	private static void sign(String[] args) throws Exception {
		String keystorePath = option(args, "--ks");
		String alias = option(args, "--ks-key-alias");
		char[] storePass = password(option(args, "--ks-pass"));
		String keyPassSpec = option(args, "--key-pass");
		char[] keyPass = keyPassSpec == null ? storePass : password(keyPassSpec);
		String input = lastFile(args);
		String output = option(args, "--out");
		if (output == null) {
			output = input;
		}
		if (keystorePath == null || input == null) {
			usage();
			System.exit(1);
		}

		KeyStore store = KeyStore.getInstance(keystorePath.endsWith(".p12") ? "PKCS12" : "JKS");
		try (FileInputStream in = new FileInputStream(keystorePath)) {
			store.load(in, storePass);
		}
		if (alias == null) {
			alias = store.aliases().nextElement();
		}
		PrivateKey key = (PrivateKey) store.getKey(alias, keyPass);
		if (key == null) {
			throw new IllegalStateException("No key '" + alias + "' in " + keystorePath);
		}
		X509Certificate certificate = (X509Certificate) store.getCertificate(alias);

		byte[] apk = Files.readAllBytes(new File(input).toPath());
		apk = stripExistingSigningBlock(apk);
		Zip zip = Zip.locate(apk);

		// The digest is taken with the end-of-central-directory record still
		// pointing at where the central directory sits *now*, because that is
		// exactly where the signing block is about to be inserted.
		byte[] digest = contentDigest(apk, zip, zip.centralDirectoryOffset);
		byte[] block = buildSigningBlock(digest, key, certificate);

		ByteArrayOutputStream out = new ByteArrayOutputStream(apk.length + block.length);
		out.write(apk, 0, zip.centralDirectoryOffset);
		out.write(block);
		out.write(apk, zip.centralDirectoryOffset, zip.centralDirectorySize);
		byte[] eocd = new byte[apk.length - zip.eocdOffset];
		System.arraycopy(apk, zip.eocdOffset, eocd, 0, eocd.length);
		writeInt(eocd, 16, zip.centralDirectoryOffset + block.length);
		out.write(eocd);

		byte[] signed = out.toByteArray();
		try (FileOutputStream file = new FileOutputStream(output)) {
			file.write(signed);
		}
		System.out.println("Signed " + output + " with APK Signature Scheme v2 ("
				+ certificate.getSubjectX500Principal() + ")");
	}

	private static byte[] buildSigningBlock(byte[] digest, PrivateKey key, X509Certificate certificate)
			throws Exception {
		byte[] certificateDer = certificate.getEncoded();

		// signed data = digests | certificates | additional attributes
		ByteArrayOutputStream digests = new ByteArrayOutputStream();
		digests.write(intBytes(SIG_ALGO_RSA_SHA256));
		digests.write(lengthPrefixed(digest));
		ByteArrayOutputStream certificates = new ByteArrayOutputStream();
		certificates.write(lengthPrefixed(certificateDer));

		ByteArrayOutputStream signedData = new ByteArrayOutputStream();
		signedData.write(lengthPrefixed(digests.toByteArray()));
		signedData.write(lengthPrefixed(certificates.toByteArray()));
		signedData.write(lengthPrefixed(new byte[0])); // no additional attributes
		byte[] signedDataBytes = signedData.toByteArray();

		Signature signer = Signature.getInstance("SHA256withRSA");
		signer.initSign(key);
		signer.update(signedDataBytes);
		byte[] signatureBytes = signer.sign();

		ByteArrayOutputStream signatures = new ByteArrayOutputStream();
		signatures.write(intBytes(SIG_ALGO_RSA_SHA256));
		signatures.write(lengthPrefixed(signatureBytes));

		ByteArrayOutputStream signerBlock = new ByteArrayOutputStream();
		signerBlock.write(lengthPrefixed(signedDataBytes));
		signerBlock.write(lengthPrefixed(signatures.toByteArray()));
		signerBlock.write(lengthPrefixed(certificate.getPublicKey().getEncoded()));

		// The v2 value is a length-prefixed sequence of length-prefixed signers.
		ByteArrayOutputStream signerList = new ByteArrayOutputStream();
		signerList.write(lengthPrefixed(signerBlock.toByteArray()));
		byte[] value = lengthPrefixed(signerList.toByteArray());

		ByteArrayOutputStream pairs = new ByteArrayOutputStream();
		pairs.write(longBytes(4L + value.length));
		pairs.write(intBytes(V2_BLOCK_ID));
		pairs.write(value);
		byte[] pairBytes = pairs.toByteArray();

		ByteArrayOutputStream block = new ByteArrayOutputStream();
		long sizeField = pairBytes.length + 8L + MAGIC.length;
		block.write(longBytes(sizeField));
		block.write(pairBytes);
		block.write(longBytes(sizeField));
		block.write(MAGIC);
		return block.toByteArray();
	}

	// --- verification -------------------------------------------------------

	private static void verify(String[] args) throws Exception {
		String input = lastFile(args);
		if (input == null) {
			usage();
			System.exit(1);
		}
		byte[] apk = Files.readAllBytes(new File(input).toPath());
		Zip zip = Zip.locate(apk);

		int blockEnd = zip.centralDirectoryOffset;
		if (blockEnd < 24 + MAGIC.length) {
			throw new IllegalStateException("APK is not signed (no signing block)");
		}
		for (int i = 0; i < MAGIC.length; i++) {
			if (apk[blockEnd - MAGIC.length + i] != MAGIC[i]) {
				throw new IllegalStateException("APK is not signed with APK Signature Scheme v2");
			}
		}
		long sizeField = readLong(apk, blockEnd - MAGIC.length - 8);
		int blockStart = (int) (blockEnd - sizeField - 8);
		if (blockStart < 0 || readLong(apk, blockStart) != sizeField) {
			throw new IllegalStateException("Malformed APK signing block");
		}

		byte[] value = null;
		ByteBuffer pairs = ByteBuffer.wrap(apk, blockStart + 8, (int) (sizeField - 8 - MAGIC.length))
				.order(ByteOrder.LITTLE_ENDIAN);
		while (pairs.remaining() >= 12) {
			long length = pairs.getLong();
			int id = pairs.getInt();
			byte[] data = new byte[(int) length - 4];
			pairs.get(data);
			if (id == V2_BLOCK_ID) {
				value = data;
			}
		}
		if (value == null) {
			throw new IllegalStateException("No v2 signature in the signing block");
		}

		ByteBuffer signers = slice(ByteBuffer.wrap(value).order(ByteOrder.LITTLE_ENDIAN));
		int verified = 0;
		while (signers.remaining() > 0) {
			ByteBuffer signer = slice(signers);
			ByteBuffer signedData = slice(signer);
			byte[] signedDataBytes = new byte[signedData.remaining()];
			signedData.duplicate().get(signedDataBytes);
			ByteBuffer signatures = slice(signer);
			byte[] publicKeyBytes = new byte[slice(signer).remaining()];

			ByteBuffer digestList = slice(signedData);
			byte[] claimedDigest = null;
			while (digestList.remaining() >= 8) {
				int algorithm = digestList.getInt();
				byte[] digest = new byte[digestList.getInt()];
				digestList.get(digest);
				if (algorithm == SIG_ALGO_RSA_SHA256) {
					claimedDigest = digest;
				}
			}
			ByteBuffer certificateList = slice(signedData);
			byte[] certificateDer = new byte[certificateList.getInt()];
			certificateList.get(certificateDer);
			X509Certificate certificate = (X509Certificate) java.security.cert.CertificateFactory
					.getInstance("X.509")
					.generateCertificate(new java.io.ByteArrayInputStream(certificateDer));

			boolean signatureOk = false;
			while (signatures.remaining() >= 8) {
				int algorithm = signatures.getInt();
				byte[] signatureBytes = new byte[signatures.getInt()];
				signatures.get(signatureBytes);
				if (algorithm != SIG_ALGO_RSA_SHA256) {
					continue;
				}
				Signature check = Signature.getInstance("SHA256withRSA");
				check.initVerify(certificate.getPublicKey());
				check.update(signedDataBytes);
				signatureOk = check.verify(signatureBytes);
			}
			if (!signatureOk) {
				throw new IllegalStateException("Signature does not match the signed data");
			}

			// Recompute the file digest. The end-of-central-directory record
			// has to be treated as if it still pointed at the signing block.
			byte[] actual = contentDigest(apk, zip, blockStart, blockStart);
			if (claimedDigest == null || !MessageDigest.isEqual(claimedDigest, actual)) {
				throw new IllegalStateException("APK contents do not match the signed digest");
			}
			System.out.println("Verified using v2 scheme (APK Signature Scheme v2): true");
			System.out.println("Signer certificate: " + certificate.getSubjectX500Principal());
			verified++;
		}
		if (verified == 0) {
			throw new IllegalStateException("No signers found");
		}
	}

	private static ByteBuffer slice(ByteBuffer source) {
		int length = source.getInt();
		ByteBuffer out = source.slice().order(ByteOrder.LITTLE_ENDIAN);
		out.limit(length);
		source.position(source.position() + length);
		return out;
	}

	// --- digest -------------------------------------------------------------

	private static byte[] contentDigest(byte[] apk, Zip zip, int eocdCentralDirectoryOffset) throws Exception {
		return contentDigest(apk, zip, zip.centralDirectoryOffset, eocdCentralDirectoryOffset);
	}

	/**
	 * The v2 digest covers three runs of bytes: everything before the signing
	 * block, the central directory, and the end-of-central-directory record
	 * with its central directory pointer rewritten to the signing block's
	 * offset. Each run is split into 1MB chunks, every chunk is hashed on its
	 * own, and the chunk hashes are then hashed together.
	 */
	private static byte[] contentDigest(byte[] apk, Zip zip, int contentsEnd,
			int eocdCentralDirectoryOffset) throws Exception {
		byte[] eocd = new byte[apk.length - zip.eocdOffset];
		System.arraycopy(apk, zip.eocdOffset, eocd, 0, eocd.length);
		writeInt(eocd, 16, eocdCentralDirectoryOffset);

		int contentsLength = contentsEnd;
		int centralDirectoryLength = zip.centralDirectorySize;

		List<byte[]> chunkDigests = new ArrayList<>();
		MessageDigest sha = MessageDigest.getInstance("SHA-256");
		int chunkCount = chunks(contentsLength) + chunks(centralDirectoryLength) + chunks(eocd.length);

		addChunks(chunkDigests, sha, apk, 0, contentsLength);
		addChunks(chunkDigests, sha, apk, zip.centralDirectoryOffset, centralDirectoryLength);
		addChunks(chunkDigests, sha, eocd, 0, eocd.length);

		sha.reset();
		sha.update((byte) 0x5a);
		sha.update(intBytes(chunkCount));
		for (byte[] chunkDigest : chunkDigests) {
			sha.update(chunkDigest);
		}
		return sha.digest();
	}

	private static int chunks(int length) {
		return (length + CHUNK_SIZE - 1) / CHUNK_SIZE;
	}

	private static void addChunks(List<byte[]> into, MessageDigest sha, byte[] source, int offset, int length) {
		int position = 0;
		while (position < length) {
			int size = Math.min(CHUNK_SIZE, length - position);
			sha.reset();
			sha.update((byte) 0xa5);
			sha.update(intBytes(size));
			sha.update(source, offset + position, size);
			into.add(sha.digest());
			position += size;
		}
	}

	// --- zip ----------------------------------------------------------------

	private static final class Zip {
		int eocdOffset;
		int centralDirectoryOffset;
		int centralDirectorySize;

		static Zip locate(byte[] apk) {
			for (int i = apk.length - 22; i >= 0; i--) {
				if (readInt(apk, i) == EOCD_SIGNATURE) {
					int commentLength = readShort(apk, i + 20);
					if (i + 22 + commentLength != apk.length) {
						continue;
					}
					Zip zip = new Zip();
					zip.eocdOffset = i;
					zip.centralDirectorySize = readInt(apk, i + 12);
					zip.centralDirectoryOffset = readInt(apk, i + 16);
					return zip;
				}
			}
			throw new IllegalStateException("Not a zip archive: no end-of-central-directory record");
		}
	}

	/** Lets re-signing work by removing any block a previous run left behind. */
	private static byte[] stripExistingSigningBlock(byte[] apk) {
		Zip zip = Zip.locate(apk);
		int blockEnd = zip.centralDirectoryOffset;
		if (blockEnd < 24 + MAGIC.length) {
			return apk;
		}
		for (int i = 0; i < MAGIC.length; i++) {
			if (apk[blockEnd - MAGIC.length + i] != MAGIC[i]) {
				return apk;
			}
		}
		long sizeField = readLong(apk, blockEnd - MAGIC.length - 8);
		int blockStart = (int) (blockEnd - sizeField - 8);
		if (blockStart < 0 || readLong(apk, blockStart) != sizeField) {
			return apk;
		}
		int blockLength = blockEnd - blockStart;
		byte[] out = new byte[apk.length - blockLength];
		System.arraycopy(apk, 0, out, 0, blockStart);
		System.arraycopy(apk, blockEnd, out, blockStart, apk.length - blockEnd);
		int newEocd = zip.eocdOffset - blockLength;
		writeInt(out, newEocd + 16, blockStart);
		return out;
	}

	// --- little endian helpers ---------------------------------------------

	private static byte[] intBytes(int value) {
		return ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(value).array();
	}

	private static byte[] longBytes(long value) {
		return ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN).putLong(value).array();
	}

	private static byte[] lengthPrefixed(byte[] payload) {
		byte[] out = new byte[4 + payload.length];
		System.arraycopy(intBytes(payload.length), 0, out, 0, 4);
		System.arraycopy(payload, 0, out, 4, payload.length);
		return out;
	}

	private static int readInt(byte[] data, int offset) {
		return ByteBuffer.wrap(data, offset, 4).order(ByteOrder.LITTLE_ENDIAN).getInt();
	}

	private static long readLong(byte[] data, int offset) {
		return ByteBuffer.wrap(data, offset, 8).order(ByteOrder.LITTLE_ENDIAN).getLong();
	}

	private static int readShort(byte[] data, int offset) {
		return ByteBuffer.wrap(data, offset, 2).order(ByteOrder.LITTLE_ENDIAN).getShort() & 0xffff;
	}

	private static void writeInt(byte[] data, int offset, int value) {
		System.arraycopy(intBytes(value), 0, data, offset, 4);
	}
}
