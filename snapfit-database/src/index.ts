/// <reference types="@cloudflare/workers-types" />
import { Router } from 'itty-router';

interface Env {
	PHOTOS_BUCKET: R2Bucket;
	PHOTO_CACHE: KVNamespace;
	THUMBNAIL_WIDTH: string;
	THUMBNAIL_HEIGHT: string;
	THUMBNAIL_QUALITY: string;
	ORIGINAL_QUALITY: string;
}

interface RequestWithParams extends Request {
	params?: {
		userId?: string;
		timestamp?: string;
		type?: string;
	};
}

interface PhotoMetadata {
	userId: string;
	takenAt: string;
	bodyFat?: number;
	weight?: number;
	thumbnailKey: string;
	originalKey: string;
}

interface PhotoListResponse {
	photos: Array<{
		metadata: PhotoMetadata;
		photoUrl: string;
		contentType: string;
		nextKey?: string;
	}>;
	cursor: string | undefined;
	hasMore: boolean;
	preloadUrls?: string[];
}

interface KVListKey {
	name: string;
	expiration?: number;
	metadata?: unknown;
}

type PhotoType = 'original' | 'thumbnail';

// Helper to generate storage keys
function generateStorageKey(userId: string, timestamp: string, type: PhotoType): string {
	return `users/${userId}/photos/${timestamp}-${type}.webp`;
}

// Convert image to WebP with specified dimensions
async function processImage(file: Uint8Array, width?: number, height?: number, quality: number = 80): Promise<ArrayBuffer> {
	return fetch('http://api.cloudflare.com/transform', {
		method: 'POST',
		body: file,
		headers: {
			'Content-Type': 'image/webp',
			'Width': width?.toString() || '',
			'Height': height?.toString() || '',
			'Quality': quality.toString(),
		},
	}).then(res => res.arrayBuffer());
}

const router = Router();

// Upload photo handler
router.post('/upload', async (request: RequestWithParams, env: Env) => {
	try {
		const { userId, timestamp, image } = await request.json() as { 
			userId: string; 
			timestamp: string; 
			image: string; 
		};

		if (!userId || !timestamp || !image) {
			return new Response('Missing required fields', { status: 400 });
		}

		const imageBuffer = new Uint8Array(Array.from(atob(image), c => c.charCodeAt(0)));
		const thumbnailKey = generateStorageKey(userId, timestamp, 'thumbnail');
		const originalKey = generateStorageKey(userId, timestamp, 'original');

		// Process and upload images in parallel
		const [[thumbnailBuffer, originalBuffer], [thumbnailResult, originalResult]] = await Promise.all([
			Promise.all([
				processImage(imageBuffer, parseInt(env.THUMBNAIL_WIDTH), parseInt(env.THUMBNAIL_HEIGHT), parseInt(env.THUMBNAIL_QUALITY)),
				processImage(imageBuffer, undefined, undefined, parseInt(env.ORIGINAL_QUALITY))
			]),
			Promise.all([
				env.PHOTOS_BUCKET.put(thumbnailKey, imageBuffer, {
					httpMetadata: { contentType: 'image/webp' },
					customMetadata: { cacheControl: 'public, max-age=31536000' },
				}),
				env.PHOTOS_BUCKET.put(originalKey, imageBuffer, {
					httpMetadata: { contentType: 'image/webp' },
					customMetadata: { cacheControl: 'public, max-age=31536000' },
				})
			])
		]);

		// Store metadata
		const metadata: PhotoMetadata = { userId, takenAt: timestamp, thumbnailKey, originalKey };
		await env.PHOTO_CACHE.put(
			`photo:${userId}:${timestamp}`,
			JSON.stringify(metadata),
			{ expirationTtl: 86400 * 30 }
		);

		return Response.json({ success: true });
	} catch (error) {
		return Response.json({ error: error instanceof Error ? error.message : 'Unknown error' }, { status: 500 });
	}
});

// Update the KVNamespaceListResult interface
interface KVNamespaceListResult<K, V> {
	keys: KVListKey[];
	list_complete: boolean;
	cursor?: string;
	cacheStatus: string | null;
}

interface PhotoResponse {
	metadata: PhotoMetadata;
	photoUrl: string;
	contentType: string;
	nextKey?: string;
}

// Get photos list with cursor-based pagination and pre-fetching
router.get('/photos/:userId', async (request: RequestWithParams, env: Env) => {
	try {
		const userId = request.params?.userId;
		if (!userId) return new Response('User ID required', { status: 400 });

		const url = new URL(request.url);
		const cursor = url.searchParams.get('cursor');
		const limit = Math.min(parseInt(url.searchParams.get('limit') || '20'), 50);
		const type = (url.searchParams.get('type') || 'thumbnail') as PhotoType;
		const preload = url.searchParams.get('preload') !== 'false';

		// Fetch current batch plus next batch for preloading
		const actualLimit = preload ? limit * 2 : limit;
		const list = await env.PHOTO_CACHE.list({ 
			prefix: `photo:${userId}:`,
			cursor: cursor || undefined,
			limit: actualLimit
		}) as KVNamespaceListResult<unknown, string>;

		// Process current batch
		const currentBatch = list.keys.slice(0, limit);
		const nextBatch = list.keys.slice(limit, actualLimit);

		const [currentPhotos, nextPhotos] = await Promise.all([
			// Process current batch
			Promise.all(
				currentBatch.map(async (key: KVListKey): Promise<PhotoResponse | null> => {
					const metadata = await env.PHOTO_CACHE.get(key.name, 'json') as PhotoMetadata;
					if (!metadata) return null;

					const photoKey = type === 'thumbnail' ? metadata.thumbnailKey : metadata.originalKey;
					const photo = await env.PHOTOS_BUCKET.get(photoKey);
					if (!photo) return null;

					return {
						metadata,
						photoUrl: photo.httpEtag,
						contentType: photo.httpMetadata?.contentType || 'image/webp',
						nextKey: key.name
					};
				})
			),
			// Pre-fetch next batch if enabled
			preload ? Promise.all(
				nextBatch.map(async (key: KVListKey): Promise<string | null> => {
					const metadata = await env.PHOTO_CACHE.get(key.name, 'json') as PhotoMetadata;
					if (!metadata) return null;

					const photoKey = type === 'thumbnail' ? metadata.thumbnailKey : metadata.originalKey;
					const photo = await env.PHOTOS_BUCKET.get(photoKey);
					if (!photo) return null;

					return photo.httpEtag;
				})
			) : Promise.resolve([])
		]);

		const validPhotos = currentPhotos.filter((photo): photo is PhotoResponse => photo !== null);
		const validPreloadUrls = nextPhotos.filter((url): url is string => url !== null);

		const response: PhotoListResponse = {
			photos: validPhotos,
			cursor: list.cursor,
			hasMore: !list.list_complete,
			preloadUrls: preload ? validPreloadUrls : undefined
		};

		return Response.json(response, {
			headers: {
				'Cache-Control': 'public, max-age=60',
				'Link': preload && response.preloadUrls?.length ? 
					response.preloadUrls.map(url => `<${url}>; rel=prefetch`).join(', ') : ''
			}
		});
	} catch (error) {
		return Response.json({ error: error instanceof Error ? error.message : 'Unknown error' }, { status: 500 });
	}
});

// Get specific photo for a user
router.get('/photos/:userId/:timestamp/:type', async (request: RequestWithParams, env: Env) => {
	try {
		const { userId, timestamp, type } = request.params || {};
		if (!userId || !timestamp || !type) {
			return new Response('Missing parameters', { status: 400 });
		}

		const metadata = await env.PHOTO_CACHE.get(`photo:${userId}:${timestamp}`, 'json') as PhotoMetadata;
		if (!metadata || metadata.userId !== userId) {
			return new Response('Photo not found', { status: 404 });
		}

		const photoKey = type === 'thumbnail' ? metadata.thumbnailKey : metadata.originalKey;
		const object = await env.PHOTOS_BUCKET.get(photoKey);
		if (!object) return new Response('Photo not found', { status: 404 });

		const headers = new Headers();
		object.writeHttpMetadata(headers);
		headers.set('Cache-Control', 'public, max-age=31536000');
		headers.set('etag', object.httpEtag);

		return new Response(object.body, { headers });
	} catch (error) {
		return Response.json({ error: error instanceof Error ? error.message : 'Unknown error' }, { status: 500 });
	}
});

// Update photo metadata
router.patch('/photos/:userId/:timestamp', async (request: RequestWithParams, env: Env) => {
	try {
		const { userId, timestamp } = request.params || {};
		if (!userId || !timestamp) {
			return new Response('Missing parameters', { status: 400 });
		}

		const updates = await request.json() as { bodyFat?: number; weight?: number };
		const key = `photo:${userId}:${timestamp}`;
		const existing = await env.PHOTO_CACHE.get(key, 'json') as PhotoMetadata;

		if (!existing) return new Response('Photo not found', { status: 404 });

		const updated: PhotoMetadata = {
			...existing,
			...(updates.bodyFat !== undefined && { bodyFat: updates.bodyFat }),
			...(updates.weight !== undefined && { weight: updates.weight })
		};

		await env.PHOTO_CACHE.put(key, JSON.stringify(updated), { expirationTtl: 86400 * 30 });
		return Response.json(updated);
	} catch (error) {
		return Response.json({ error: error instanceof Error ? error.message : 'Unknown error' }, { status: 500 });
	}
});

export default {
	fetch: router.handle
} satisfies ExportedHandler;
