const express = require('express');
const router = express.Router();
const categoryController = require('../controllers/categoryController');
const { verifyCache, invalidateAfterResponse } = require('../middleware/cacheMiddleware');

// GET /api/categories -> Lấy danh sách
router.get('/', verifyCache(300), categoryController.getCategories);

// POST /api/categories -> Tạo mới
router.post('/', invalidateAfterResponse('/api/categories', '/api/products'), categoryController.createCategory);

// DELETE /api/categories/:id -> Xóa
router.delete('/:id', invalidateAfterResponse('/api/categories', '/api/products'), categoryController.deleteCategory);

router.put('/:id/visibility', invalidateAfterResponse('/api/categories'), categoryController.toggleCategoryVisibility);

module.exports = router;
