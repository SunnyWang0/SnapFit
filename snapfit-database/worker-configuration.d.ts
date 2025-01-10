/// <reference types="@cloudflare/workers-types" />

interface Env {
  PHOTOS_BUCKET: R2Bucket;
  PHOTO_CACHE: KVNamespace;
  THUMBNAIL_WIDTH: string;
  THUMBNAIL_HEIGHT: string;
  THUMBNAIL_QUALITY: string;
  ORIGINAL_QUALITY: string;
}
