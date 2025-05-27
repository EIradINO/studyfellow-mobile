import {region as regionV1, EventContext} from "firebase-functions/v1";
import {UserRecord as AuthUserRecord} from "firebase-functions/v1/auth"; // v1 auth UserRecord
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

// Firebase Admin SDKの初期化（すでに行われていなければ）
if (admin.apps.length === 0) {
  admin.initializeApp();
}
const db = admin.firestore();

function generateRandomAlphanumeric(length: number): string {
  const characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
  let result = "";
  const charactersLength = characters.length;
  for (let i = 0; i < length; i++) {
    result += characters.charAt(Math.floor(Math.random() * charactersLength));
  }
  return result;
}

export const onCreateUserDocument = regionV1("asia-northeast1")
  .auth.user().onCreate(async (user: AuthUserRecord, context: EventContext) => {
    // user は AuthUserRecord オブジェクト
    logger.info(`User created: ${user.uid}`, {user});

    const uid = user.uid;
    const displayName = user.displayName || ""; // Googleログインなら通常存在するが、念のためフォールバック
    const createdAt = admin.firestore.FieldValue.serverTimestamp(); // Firestoreのサーバータイムスタンプ
    const userName = generateRandomAlphanumeric(12);

    const userData = {
      uid: uid,
      created_at: createdAt,
      display_name: displayName,
      user_name: userName,
      // 必要に応じて他の初期フィールドを追加
    };

    logger.info(`Attempting to create user document for UID: ${uid}`, userData);

    try {
      await db.collection("users").doc(uid).set(userData);
      logger.info(`Successfully created user document for UID: ${uid}`);
    } catch (error) {
      logger.error(`Error creating user document for UID: ${uid}:`, error);
    }
    return null;
  }); 