// Single firebase-admin init point. Every handler / trigger / tool imports
// `db` from here. Calling initializeApp twice throws — keep it here only.
import { initializeApp, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

if (getApps().length === 0) {
  initializeApp();
}

export const db = getFirestore();
export const REGION = 'us-west1';
