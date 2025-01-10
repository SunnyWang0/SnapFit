# SnapFit Worker Implementation Guide

## Overview

The SnapFit worker handles photo storage, retrieval, and metadata management using Cloudflare's edge infrastructure. It's designed for optimal performance with smooth scrolling through both thumbnails and full-size images.

## Storage Architecture

### R2 Storage

- Photos are stored in Cloudflare R2 in two formats:
  - Original: High-quality WebP (80% quality)
  - Thumbnail: 200x200px WebP (60% quality)
- Storage path structure: `users/${userId}/photos/${timestamp}-${type}.webp`
- Built-in encryption via R2
- Aggressive caching (1 year) for both formats

### KV Cache

- Metadata stored in KV for fast retrieval
- 30-day cache duration for metadata
- Cursor-based pagination for efficient listing
- Key format: `photo:${userId}:${timestamp}`

## API Endpoints

### 1. Upload Photo

```typescript
POST / upload;
Body: {
	userId: string;
	timestamp: string;
	image: string; // base64 encoded
}
```

Features:

- Parallel processing of thumbnail and original
- WebP conversion for optimal size
- Automatic metadata storage
- Error handling with type safety

### 2. List Photos

```typescript
GET /photos/:userId?cursor=<cursor>&limit=20&type=thumbnail
```

Features:

- Cursor-based pagination (max 50 per request)
- Pre-fetching of next batch
- Supports both thumbnail and original listings
- Returns pre-load URLs for smooth scrolling

Response:

```typescript
{
  photos: Array<{
    metadata: PhotoMetadata;
    photoUrl: string;
    contentType: string;
    nextKey?: string;
  }>;
  cursor?: string;
  hasMore: boolean;
  preloadUrls?: string[];
}
```

### 3. Get Specific Photo

```typescript
GET /photos/:userId/:timestamp/:type
```

Features:

- Direct R2 access
- Type-safe error handling
- Ownership verification
- Aggressive caching

### 4. Update Metadata

```typescript
PATCH /photos/:userId/:timestamp
Body: {
  bodyFat?: number;
  weight?: number;
}
```

Features:

- Atomic updates
- Type-safe validation
- Automatic cache management

## Type Safety and Error Handling

### Worker Types

```typescript
// Photo metadata structure
interface PhotoMetadata {
	userId: string;
	takenAt: string;
	bodyFat?: number;
	weight?: number;
	thumbnailKey: string;
	originalKey: string;
}

// API response types
interface PhotoResponse {
	metadata: PhotoMetadata;
	photoUrl: string;
	contentType: string;
	nextKey?: string;
}

interface PhotoListResponse {
	photos: PhotoResponse[];
	cursor?: string;
	hasMore: boolean;
	preloadUrls?: string[];
}
```

### iOS Types

```swift
// Match the worker types
struct PhotoMetadata: Codable {
    let userId: String
    let takenAt: String
    let bodyFat: Double?
    let weight: Double?
    let thumbnailKey: String
    let originalKey: String
}

struct PhotoResponse: Codable {
    let metadata: PhotoMetadata
    let photoUrl: String
    let contentType: String
    let nextKey: String?
}

struct PhotoListResponse: Codable {
    let photos: [PhotoResponse]
    let cursor: String?
    let hasMore: Bool
    let preloadUrls: [String]?
}
```

## iOS Integration Details

### PhotoService Implementation

````swift
class PhotoService {
    private let baseUrl: URL
    private let session: URLSession
    private let cache: NSCache<NSString, UIImage>
    private let fileManager: FileManager

    // Background upload queue
    private let uploadQueue: OperationQueue

    init(baseUrl: URL) {
        self.baseUrl = baseUrl

        // Configure session for background uploads
        let config = URLSessionConfiguration.background(withIdentifier: "com.snapfit.upload")
        config.isDiscretionary = true
        config.sessionSendsLaunchEvents = true
        self.session = URLSession(configuration: config)

        // Configure cache
        self.cache = NSCache<NSString, UIImage>()
        cache.countLimit = 100 // Max number of thumbnails
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB limit

        // Configure upload queue
        uploadQueue = OperationQueue()
        uploadQueue.maxConcurrentOperationCount = 1

        setupNotifications()
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    @objc private func handleMemoryWarning() {
        cache.removeAllObjects()
    }
}

// MARK: - Photo Loading
extension PhotoService {
    func loadThumbnails(userId: String, cursor: String? = nil) async throws -> PhotoListResponse {
        let url = baseUrl
            .appendingPathComponent("photos")
            .appendingPathComponent(userId)

        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "type", value: "thumbnail"),
            URLQueryItem(name: "limit", value: "20")
        ]

        if let cursor {
            components.queryItems?.append(URLQueryItem(name: "cursor", value: cursor))
        }

        let response = try await fetch(components.url!)

        // Start pre-fetching
        if let preloadUrls = response.preloadUrls {
            Task.detached(priority: .utility) {
                await self.prefetchImages(preloadUrls)
            }
        }

        return response
    }

    private func prefetchImages(_ urls: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask {
                    try? await self.prefetchImage(url)
                }
            }
        }
    }
}

// MARK: - Upload Handling
extension PhotoService {
    func uploadPhoto(image: UIImage, userId: String) async throws -> UploadResponse {
        let operation = PhotoUploadOperation(image: image, userId: userId, service: self)
        uploadQueue.addOperation(operation)

        return try await operation.result.value
    }

    func retryFailedUploads() {
        // Implement retry logic for failed uploads
        let failedUploads = loadFailedUploadsFromDisk()
        for upload in failedUploads {
            let operation = PhotoUploadOperation(
                image: upload.image,
                userId: upload.userId,
                service: self
            )
            uploadQueue.addOperation(operation)
        }
    }
}

// MARK: - Error Handling
extension PhotoService {
    enum PhotoError: Error {
        case compressionFailed
        case networkError(Error)
        case serverError(String)
        case rateLimited(retryAfter: TimeInterval)

        var isRetryable: Bool {
            switch self {
            case .compressionFailed: return false
            case .networkError: return true
            case .serverError: return true
            case .rateLimited: return true
            }
        }
    }

    private func handleError(_ error: Error) async throws {
        guard let photoError = error as? PhotoError else {
            throw error
        }

        switch photoError {
        case .rateLimited(let retryAfter):
            try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
            // Retry the operation

        case .networkError where photoError.isRetryable:
            // Implement exponential backoff
            try await performRetryWithBackoff()

        default:
            throw error
        }
    }
}

## Advanced Features

### 1. Offline Support
```swift
class OfflineStorage {
    private let store: CoreDataStore

    func cachePhotosLocally(_ photos: [PhotoResponse]) {
        // Store photos and metadata in Core Data
        store.savePhotos(photos)
    }

    func loadCachedPhotos() -> [PhotoResponse] {
        // Load cached photos when offline
        return store.loadPhotos()
    }
}
````

### 2. Background Processing

```swift
class BackgroundTaskManager {
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    func beginBackgroundTask() {
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
    }

    func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
}
```

### 3. Image Processing

```swift
extension UIImage {
    func preparingForUpload() -> UIImage? {
        let maxDimension: CGFloat = 2048
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1)

        let newSize = CGSize(
            width: size.width * scale,
            height: size.height * scale
        )

        return resized(to: newSize)
    }
}

## Performance Considerations

1. **Caching Strategy**

   - Thumbnails: In-memory cache with size limits
   - Full images: Disk cache with TTL
   - Metadata: Local persistence with sync

2. **Network Optimization**

   - Use HTTP/2 for concurrent requests
   - Implement retry with exponential backoff
   - Monitor bandwidth usage

3. **UI Responsiveness**

   - Always show placeholders first
   - Progressive loading for full-size images
   - Background processing for uploads

4. **Error Recovery**
   - Implement offline support
   - Queue failed uploads
   - Auto-retry on network restore
```
