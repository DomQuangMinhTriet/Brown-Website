const express = require('express');
const router = express.Router();
const contentController = require('../controllers/contentController');
const { verifyCache } = require('../middleware/cacheMiddleware');
const requireAuth = require('../middleware/authMiddleware');

// Public: Lấy banner (Cache 5 phút)
router.get('/banners', verifyCache(300), contentController.getBanners);

// Private: Admin quản lý (Sau này nhớ thêm middleware check Auth vào đây)
router.post('/banners', contentController.createBanner);
router.put('/banners/:id', contentController.updateBanner);
router.delete('/banners/:id', contentController.deleteBanner);

// Lookbook (editorial)
router.get('/lookbook', verifyCache(300), contentController.getLookbook);
router.post('/lookbook', contentController.createLookbook);
router.put('/lookbook/:id', contentController.updateLookbook);
router.delete('/lookbook/:id', contentController.deleteLookbook);

// Static policy pages. Reading is public; changes require an authenticated admin.
router.get('/policies/:slug', verifyCache(300), contentController.getPolicy);
router.put('/policies/:slug', requireAuth, contentController.updatePolicy);

module.exports = router;
