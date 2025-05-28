import * as logger from "firebase-functions/logger";
import {AuthBlockingEvent, beforeUserCreated} from "firebase-functions/v2/identity";
import {initializeApp, getApps} from "firebase-admin/app";
import {getFirestore} from "firebase-admin/firestore";
import { UserRecord } from 'firebase-admin/auth';

// getApps() を使って、既に初期化されているか確認
if (getApps().length === 0) {
  initializeApp();
}

// ランダムなユーザー名を生成する簡単な関数
const generateRandomUserName = (): string => {
  const randomSuffix = Math.random().toString(36).substring(2, 10);
  return `user_${randomSuffix}`;
};

export const createUserData = beforeUserCreated(async (event: AuthBlockingEvent) => {
  if (!event.data) {
    logger.error("Event data is missing");
    return;
  }
  logger.info("New user creation process started:", event.data.uid);

  const {uid, displayName, email, photoURL} = event.data as UserRecord;

  const finalDisplayName = displayName || "";

  const newUser = {
    user_id: uid,
    user_name: generateRandomUserName(),
    display_name: finalDisplayName,
    email: email || "",
    photo_url: photoURL || "",
    created_at: new Date(),
  };

  try {
    const firestore = getFirestore();
    await firestore.collection("users").doc(uid).set(newUser);
    logger.info("User data created in Firestore for user:", uid);
    return;
  } catch (error) {
    logger.error("Error creating user data in Firestore:", error);
    throw new Error(`Failed to create user data for user ${uid}`);
  }
});
