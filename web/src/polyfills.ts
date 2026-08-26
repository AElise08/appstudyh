/** Polyfills exigidos pelo pdf.js 6 em ambientes sem ES2027 completo (ex.: Electron/Cursor). */

declare global {
  interface Map<K, V> {
    getOrInsertComputed?(key: K, callback: (key: K) => V): V;
  }
}

if (typeof Map.prototype.getOrInsertComputed !== "function") {
  Object.defineProperty(Map.prototype, "getOrInsertComputed", {
    value<K, V>(this: Map<K, V>, key: K, callbackFn: (key: K) => V): V {
      if (this.has(key)) return this.get(key) as V;
      const value = callbackFn(key);
      this.set(key, value);
      return value;
    },
    writable: true,
    configurable: true,
  });
}

if (typeof (Promise as unknown as { withResolvers?: unknown }).withResolvers !== "function") {
  Object.assign(Promise, {
    withResolvers<T>() {
      let resolve!: (value: T | PromiseLike<T>) => void;
      let reject!: (reason?: unknown) => void;
      const promise = new Promise<T>((res, rej) => {
        resolve = res;
        reject = rej;
      });
      return { promise, resolve, reject };
    },
  });
}

export {};
