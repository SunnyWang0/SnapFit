declare module 'itty-router' {
  export interface IRequest extends Request {
    params?: {
      [key: string]: string;
    };
  }

  export interface RouterType {
    handle: (request: IRequest, ...args: any[]) => Promise<Response>;
    get: (path: string, handler: (request: IRequest, ...args: any[]) => Promise<Response>) => RouterType;
    post: (path: string, handler: (request: IRequest, ...args: any[]) => Promise<Response>) => RouterType;
    put: (path: string, handler: (request: IRequest, ...args: any[]) => Promise<Response>) => RouterType;
    patch: (path: string, handler: (request: IRequest, ...args: any[]) => Promise<Response>) => RouterType;
    delete: (path: string, handler: (request: IRequest, ...args: any[]) => Promise<Response>) => RouterType;
  }

  export function Router(): RouterType;
}

// Extend KVNamespace types
declare interface KVNamespaceListResult<K, V> {
  keys: KVNamespaceListKey<K, V>[];
  list_complete: boolean;
  cursor?: string;
  cacheStatus: string | null;
} 