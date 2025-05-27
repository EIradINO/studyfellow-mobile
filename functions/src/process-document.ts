import * as logger from "firebase-functions/logger";
import {onObjectFinalized, StorageEvent, onObjectDeleted} from "firebase-functions/v2/storage";
import * as admin from "firebase-admin";
import pdfParse from "pdf-parse";
import { PDFDocument } from "pdf-lib";
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";

// Firebase Admin SDKの初期化（すでに行われていなければ）
if (admin.apps.length === 0) {
  admin.initializeApp();
}

const db = admin.firestore(); // Firestoreインスタンスの取得

export const processDocument = onObjectFinalized(
  {
    bucket: "studyfellow-42d35.firebasestorage.app",
    region: "asia-northeast1",
    timeoutSeconds: 30,
    memory: "4GiB",
    maxInstances: 200,
  },
  async (event: StorageEvent) => {
    logger.info("Storage event received for processDocument:", event);

    const filePath = event.data.name;
    const contentType = event.data.contentType;
    const metageneration = event.data.metageneration;

    if (metageneration && parseInt(String(metageneration), 10) > 1) {
        logger.log(`File ${filePath} is a metadata update, not a new file. Skipping processing.`);
        return null;
    }

    if (!filePath || !filePath.startsWith("raw_documents/") || !contentType || !contentType.startsWith("application/pdf")) {
      logger.log(
        `File ${filePath} with contentType ${contentType} is not a PDF in raw_documents folder. Skipping processing.`
      );
      return null;
    }

    const fileName = filePath.split("/").pop() || "unknown.pdf";
    const fileSize = parseInt(String(event.data.size || "0"), 10);
    const createdAt = event.data.timeCreated ? new Date(event.data.timeCreated) : new Date();

    let totalPages = 0;
    let subject = "";
    try {
      const bucket = admin.storage().bucket(event.data.bucket);
      const file = bucket.file(filePath);
      const [fileBuffer] = await file.download();
      const data = await pdfParse(fileBuffer);
      totalPages = data.numpages;
      logger.info(`Successfully parsed PDF: ${filePath}, total pages: ${totalPages}`);

      if (totalPages > 0) {
        const pdfDoc = await PDFDocument.load(fileBuffer);
        const originalFileNameWithoutExt = fileName.substring(0, fileName.lastIndexOf("."));
        const relativePath = filePath.substring("raw_documents/".length);
        const lastSlashIndex = relativePath.lastIndexOf("/");
        const originalPathDir = lastSlashIndex > -1 ? relativePath.substring(0, lastSlashIndex) : "";

        for (let i = 0; i < totalPages; i++) {
          const subDocument = await PDFDocument.create();
          const [copiedPage] = await subDocument.copyPages(pdfDoc, [i]);
          subDocument.addPage(copiedPage);
          const pdfBytes = await subDocument.save();
          
          const newFilePath = `split_documents/${originalPathDir ? `${originalPathDir}/` : ''}${originalFileNameWithoutExt}/page${i + 1}.pdf`;
          
          const newFile = bucket.file(newFilePath);
          await newFile.save(Buffer.from(pdfBytes), {
            contentType: "application/pdf",
          });
          logger.info(`Saved page ${i + 1} of ${filePath} to ${newFilePath}`);
        }
      }
    } catch (error) {
      logger.error(`Failed to parse PDF ${filePath} or get page count:`, error);
    }

    if (filePath.startsWith("raw_documents/")) {
      const pathParts = filePath.substring("raw_documents/".length).split("/");
      if (pathParts.length > 1) {
        subject = pathParts[0];
      }
    }

    const documentData = {
      created_at: createdAt,
      file_name: fileName,
      file_size: fileSize,
      path: filePath,
      status: "unprocessed",
      title: "",
      total_pages: totalPages,
      subject: subject,
      sub_ids: [],
    };

    logger.info("Attempting to save metadata to Firestore:", documentData);

    try {
      const collectionPath = "document_metadata";
      const docRef = await db.collection(collectionPath).add(documentData);
      logger.log(`Metadata for ${filePath} saved successfully to Firestore at ${collectionPath}/${docRef.id}.`);
      return null;
    } catch (error) {
      logger.error(`Error saving metadata for ${filePath} to Firestore:`, error);
      throw error;
    }
  }
);

export const handleDocumentDeletion = onObjectDeleted(
  {
    bucket: "studyfellow-42d35.firebasestorage.app",
    region: "asia-northeast1",
    timeoutSeconds: 30,
    memory: "4GiB",
    maxInstances: 200,
  },
  async (event: StorageEvent) => {
    logger.info("Storage deletion event received for handleDocumentDeletion:", event);

    const filePath = event.data.name;
    const contentType = event.data.contentType;

    if (!filePath || !filePath.startsWith("raw_documents/") || !(filePath.toLowerCase().endsWith(".pdf") || (contentType && contentType.startsWith("application/pdf")))) {
      logger.log(
        `File ${filePath} is not a PDF in raw_documents folder or contentType is missing. Skipping status update.`
      );
      return null;
    }

    logger.info(`PDF file ${filePath} was deleted. Attempting to update Firestore status and delete split documents.`);

    try {
      const collectionPath = "document_metadata";
      const querySnapshot = await db.collection(collectionPath).where("path", "==", filePath).limit(1).get();

      if (!querySnapshot.empty) {
        const docSnap = querySnapshot.docs[0];
        await docSnap.ref.update({ status: "deleted" });
        logger.log(`Status for document ${collectionPath}/${docSnap.id} (path: ${filePath}) updated to "deleted" in Firestore.`);
      } else {
        logger.log(`Document with path ${filePath} not found in Firestore collection ${collectionPath}. No status update needed for Firestore.`);
      }

      const bucket = admin.storage().bucket(event.data.bucket);
      const originalFileName = filePath.split("/").pop() || "unknown.pdf"; // fileName is correct variable name from context
      const originalFileNameWithoutExt = originalFileName.substring(0, originalFileName.lastIndexOf("."));
      const relativePathForSplit = filePath.substring("raw_documents/".length);
      const lastSlashIndexForSplit = relativePathForSplit.lastIndexOf("/");
      const originalPathDirForSplit = lastSlashIndexForSplit > -1 ? relativePathForSplit.substring(0, lastSlashIndexForSplit) : "";
      
      const splitFilesDir = `split_documents/${originalPathDirForSplit ? `${originalPathDirForSplit}/` : ''}${originalFileNameWithoutExt}/`;

      logger.info(`Attempting to delete files in directory: ${splitFilesDir}`);
      
      const [files] = await bucket.getFiles({ prefix: splitFilesDir });
      if (files.length > 0) {
        await Promise.all(files.map(file => file.delete()));
        logger.log(`Successfully deleted ${files.length} split document(s) from ${splitFilesDir}`);
      } else {
        logger.log(`No split documents found in ${splitFilesDir} to delete.`);
      }

      return null;
    } catch (error) {
      logger.error(`Error during deletion process for ${filePath} in Firestore or Storage:`, error);
      throw error;
    }
  }
);

export const deleteSplitDocumentsFolder = onCall(async (request: CallableRequest<unknown>) => {
  // 認証チェック（オプション）
  // if (!request.auth) {
  //   throw new HttpsError('unauthenticated', 'The function must be called while authenticated.');
  // }

  logger.info("Attempting to delete all files and subfolders in split_documents folder.");

  const bucket = admin.storage().bucket("studyfellow-42d35.firebasestorage.app"); 
  const prefix = "split_documents/";

  try {
    // prefixに一致するすべてのファイルとフォルダ内のファイルを削除
    await bucket.deleteFiles({ 
      prefix: prefix,
      force: true // オプション: ファイルが存在しない場合にエラーをスローしない
    });

    logger.info(`Successfully deleted all files and subfolders from ${prefix}`);
    return { message: `Successfully deleted all files and subfolders from ${prefix}` };

  } catch (error) {
    logger.error(`Error deleting files from ${prefix}:`, error);
    throw new HttpsError('internal', 'Unable to delete files.', error);
  }
});