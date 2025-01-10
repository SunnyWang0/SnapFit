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

## iOS Implementation Guide

### Setup

```swift
class PhotoService {
    private let baseUrl = "https://your-worker.workers.dev"
    private let session = URLSession.shared
}
```

### Thumbnail List View

```swift
func fetchThumbnails(userId: String, cursor: String? = nil) async throws -> PhotoListResponse {
    let url = "\(baseUrl)/photos/\(userId)?type=thumbnail&limit=20"
        + (cursor.map { "&cursor=\($0)" } ?? "")

    let response = try await fetch(url)

    // Handle pre-fetching
    if let preloadUrls = response.preloadUrls {
        Task {
            await prefetchImages(preloadUrls)
        }
    }

    return response
}

// UICollectionView implementation
func configureCollectionView() {
    collectionView.prefetchDataSource = self
    // Use UICollectionViewDiffableDataSource for smooth updates
}
```

### Full-Size Image View

```swift
func fetchFullSizePhotos(userId: String, timestamp: String) async throws -> PhotoResponse {
    let url = "\(baseUrl)/photos/\(userId)/\(timestamp)/original"
    return try await fetch(url)
}

// Pre-fetch next/previous images
func prefetchAdjacentImages(currentIndex: Int) {
    guard let photos = currentPhotoList else { return }

    let nextIndex = currentIndex + 1
    if nextIndex < photos.count {
        Task {
            await prefetchImage(photos[nextIndex].photoUrl)
        }
    }
}
```

### Upload Implementation

```swift
func uploadPhoto(image: UIImage, userId: String) async throws -> UploadResponse {
    guard let imageData = image.jpegData(compressionQuality: 0.8) else {
        throw PhotoError.compressionFailed
    }

    let base64Image = imageData.base64EncodedString()
    let timestamp = ISO8601DateFormatter().string(from: Date())

    let body = [
        "userId": userId,
        "timestamp": timestamp,
        "image": base64Image
    ]

    return try await post("\(baseUrl)/upload", body: body)
}
```

### Optimizations

1. **Smooth Scrolling**

   - Use UICollectionViewPrefetching
   - Implement placeholder thumbnails
   - Cache images in memory and disk

   ```swift
   let cache = NSCache<NSString, UIImage>()
   ```

2. **Memory Management**

   - Implement proper image downsampling
   - Clear cache when memory warnings occur

   ```swift
   NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification)
   ```

3. **Error Handling**

   - Implement retry logic for failed requests
   - Show appropriate UI feedback

   ```swift
   func handleError(_ error: Error) {
       if case let NetworkError.rateLimited(retryAfter) = error {
           scheduleRetry(after: retryAfter)
       }
   }
   ```

4. **Background Upload**
   - Support background upload tasks
   ```swift
   let config = URLSessionConfiguration.background(withIdentifier: "com.snapfit.upload")
   let session = URLSession(configuration: config)
   ```

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
