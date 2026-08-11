import axios from 'axios';

const responseCache = new Map();
const inflight = new Map();

export const cachedGet = (url, ttl = 60_000) => {
  const now = Date.now();
  const cached = responseCache.get(url);
  if (cached && cached.expiresAt > now) return Promise.resolve(cached.response);
  if (inflight.has(url)) return inflight.get(url);

  const request = axios.get(url)
    .then((response) => {
      responseCache.set(url, { response, expiresAt: Date.now() + ttl });
      inflight.delete(url);
      return response;
    })
    .catch((error) => {
      inflight.delete(url);
      throw error;
    });

  inflight.set(url, request);
  return request;
};

export const clearApiCache = (urlPart = '') => {
  for (const key of responseCache.keys()) {
    if (!urlPart || key.includes(urlPart)) responseCache.delete(key);
  }
};
