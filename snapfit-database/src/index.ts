import { Router, IRequest } from 'itty-router';
import { Buffer } from 'buffer';

interface Env {
	PHOTOS_BUCKET: R2Bucket;
	PHOTO_CACHE: KVNamespace;
	THUMBNAIL_WIDTH: string;
	THUMBNAIL_HEIGHT: string;
	THUMBNAIL_QUALITY: string;
	ORIGINAL_QUALITY: string;
}

interface PhotoMetadata {
	userId: string;
	takenAt: string;
	bodyFat?: number;
	weight?: number;
	thumbnailKey: string;
	originalKey: string;
}

interface UploadRequest {
	userId: string;
	timestamp: string;
	image: string;
}

interface UpdateRequest {
	bodyFat?: number;
	weight?: number;
}

const router = Router();

// Helper to generate storage keys
function generateStorageKey(userId: string, timestamp: string, type: 'original' | 'thumbnail'): string {
	return `users/${userId}/photos/${timestamp}-${type}.webp`;
}

// Convert image to WebP with specified dimensions
async function processImage(file: ArrayBuffer, width?: number, height?: number, quality: number = 80): Promise<ArrayBuffer> {
	const image = await fetch('http://api.cloudflare.com/transform', {
		method: 'POST',
		body: file,
		headers: {
			'Content-Type': 'image/webp',
			'Width': width?.toString() || '',
			'Height': height?.toString() || '',
			'Quality': quality.toString(),
		},
	}).then(res => res.arrayBuffer());
	
	return image;
}

// Upload photo handler
router.post('/upload', async (request: IRequest, env: Env) => {
	try {
		const data = await request.json() as UploadRequest;
		const { userId, timestamp, image } = data;
		
		if (!userId || !timestamp || !image) {
			return new Response('Missing required fields', { status: 400 });
		}

		const imageBuffer = Buffer.from(image, 'base64');
		const thumbnailKey = generateStorageKey(userId, timestamp, 'thumbnail');
		const originalKey = generateStorageKey(userId, timestamp, 'original');

		// Process images in parallel
		const [thumbnailBuffer, originalBuffer] = await Promise.all([
			processImage(
				imageBuffer, 
				parseInt(env.THUMBNAIL_WIDTH), 
				parseInt(env.THUMBNAIL_HEIGHT), 
				parseInt(env.THUMBNAIL_QUALITY)
			),
			processImage(imageBuffer, undefined, undefined, parseInt(env.ORIGINAL_QUALITY))
		]);

		// Upload to R2 in parallel
		await Promise.all([
			env.PHOTOS_BUCKET.put(thumbnailKey, thumbnailBuffer, {
				httpMetadata: { contentType: 'image/webp' },
				customMetadata: { cacheControl: 'public, max-age=31536000' },
			}),
			env.PHOTOS_BUCKET.put(originalKey, originalBuffer, {
				httpMetadata: { contentType: 'image/webp' },
				customMetadata: { cacheControl: 'public, max-age=31536000' },
			})
		]);

		// Store metadata in KV for fast retrieval
		const metadata: PhotoMetadata = {
			userId,
			takenAt: timestamp,
			thumbnailKey,
			originalKey,
		};
		
		await env.PHOTO_CACHE.put(
			`photo:${userId}:${timestamp}`,
			JSON.stringify(metadata),
			{ expirationTtl: 86400 * 30 } // 30 days cache
		);

		return new Response(JSON.stringify({ success: true }), {
			headers: { 'Content-Type': 'application/json' },
		});
	} catch (error) {
		const errorMessage = error instanceof Error ? error.message : 'Unknown error occurred';
		return new Response(JSON.stringify({ error: errorMessage }), {
			status: 500,
			headers: { 'Content-Type': 'application/json' },
		});
	}
});

// Get photos list with cursor-based pagination
router.get('/photos/:userId', async (request: IRequest, env: Env) => {
	try {
		const userId = request.params?.userId;
		if (!userId) {
			return new Response('User ID is required', { status: 400 });
		}

		const url = new URL(request.url);
		const cursor = url.searchParams.get('cursor');
		const limit = parseInt(url.searchParams.get('limit') || '10');

		const prefix = `photo:${userId}:`;
		const list = await env.PHOTO_CACHE.list({ prefix, cursor: cursor || undefined, limit });
		
		const photos = await Promise.all(
			list.keys.map(async key => {
				const metadata = await env.PHOTO_CACHE.get(key.name, 'json') as PhotoMetadata;
				return metadata;
			})
		);

		return new Response(
			JSON.stringify({
				photos,
				cursor: list.cursor,
				hasMore: !list.list_complete,
			}),
			{
				headers: {
					'Content-Type': 'application/json',
					'Cache-Control': 'public, max-age=60', // Cache for 1 minute
				},
			}
		);
	} catch (error) {
		const errorMessage = error instanceof Error ? error.message : 'Unknown error occurred';
		return new Response(JSON.stringify({ error: errorMessage }), {
			status: 500,
			headers: { 'Content-Type': 'application/json' },
		});
	}
});

// Get photo (original or thumbnail)
router.get('/photo/:key', async (request: IRequest, env: Env) => {
	try {
		const key = request.params?.key;
		if (!key) {
			return new Response('Key is required', { status: 400 });
		}

		const url = new URL(request.url);
		const type = url.searchParams.get('type') || 'thumbnail';

		// Try to get from R2
		const object = await env.PHOTOS_BUCKET.get(key);
		if (!object) {
			return new Response('Photo not found', { status: 404 });
		}

		const headers = new Headers();
		object.writeHttpMetadata(headers);
		headers.set('Cache-Control', 'public, max-age=31536000'); // Cache for 1 year
		headers.set('etag', object.httpEtag);

		return new Response(object.body, { headers });
	} catch (error) {
		const errorMessage = error instanceof Error ? error.message : 'Unknown error occurred';
		return new Response(JSON.stringify({ error: errorMessage }), {
			status: 500,
			headers: { 'Content-Type': 'application/json' },
		});
	}
});

// Update photo metadata (body fat, weight)
router.patch('/photo/:userId/:timestamp', async (request: IRequest, env: Env) => {
	try {
		const userId = request.params?.userId;
		const timestamp = request.params?.timestamp;
		
		if (!userId || !timestamp) {
			return new Response('User ID and timestamp are required', { status: 400 });
		}

		const updates = await request.json() as UpdateRequest;
		const key = `photo:${userId}:${timestamp}`;
		const existing = await env.PHOTO_CACHE.get(key, 'json') as PhotoMetadata | null;
		
		if (!existing) {
			return new Response('Photo not found', { status: 404 });
		}

		const updated: PhotoMetadata = {
			...existing,
			...(updates.bodyFat !== undefined ? { bodyFat: updates.bodyFat } : {}),
			...(updates.weight !== undefined ? { weight: updates.weight } : {})
		};

		await env.PHOTO_CACHE.put(key, JSON.stringify(updated), {
			expirationTtl: 86400 * 30 // 30 days cache
		});

		return new Response(JSON.stringify(updated), {
			headers: { 'Content-Type': 'application/json' },
		});
	} catch (error) {
		const errorMessage = error instanceof Error ? error.message : 'Unknown error occurred';
		return new Response(JSON.stringify({ error: errorMessage }), {
			status: 500,
			headers: { 'Content-Type': 'application/json' },
		});
	}
});

export default {
	fetch: router.handle
} satisfies ExportedHandler<Env>;
