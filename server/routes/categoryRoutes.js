const express = require('express');
const router = express.Router();
const categoryController = require('../controllers/categoryController');

// GET /api/categories -> Lấy danh sách
router.get('/', categoryController.getCategories);

// POST /api/categories -> Tạo mới
router.post('/', categoryController.createCategory);

// DELETE /api/categories/:id -> Xóa
router.delete('/:id', categoryController.deleteCategory);

router.put('/:id/visibility', categoryController.toggleCategoryVisibility);

module.exports = router;