const NodeCache = require('node-cache');

const cache = new NodeCache({ stdTTL: 300, useClones: false });

const clearCache = (keyPart) => {
    const matches = cache.keys().filter((key) => key.includes(keyPart));
    if (matches.length) cache.del(matches);
};

const verifyCache = (duration = 300) => (req, res, next) => {
    try {
        if (req.query?.admin === 'true' || req.headers.authorization) {
            res.setHeader('Cache-Control', 'private, no-store');
            return next();
        }
        const key = '__express__' + (req.originalUrl || req.url);
        const cachedBody = cache.get(key);

        res.setHeader('Cache-Control', 'public, max-age=0, must-revalidate');
        if (cachedBody !== undefined) {
            res.setHeader('X-Cache', 'HIT');
            return res.json(cachedBody);
        }

        res.setHeader('X-Cache', 'MISS');
        const sendJson = res.json.bind(res);
        res.json = (body) => {
            if (res.statusCode >= 200 && res.statusCode < 300) cache.set(key, body, duration);
            return sendJson(body);
        };
        next();
    } catch (error) {
        console.error('Cache Error:', error);
        next();
    }
};

const invalidateAfterResponse = (...keyParts) => (req, res, next) => {
    res.once('finish', () => {
        if (res.statusCode >= 200 && res.statusCode < 400) keyParts.forEach(clearCache);
    });
    next();
};

module.exports = { verifyCache, clearCache, invalidateAfterResponse };
