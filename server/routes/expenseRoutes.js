const express = require('express');
const router = express.Router();
const expenseController = require('../controllers/expenseController');

router.get('/', expenseController.getExpenses);
router.post('/', expenseController.createExpense);
router.delete('/:id', expenseController.deleteExpense);
router.get('/categories', expenseController.getCategories);
// Route tạo danh mục mới
router.post('/categories', expenseController.createCategory);

module.exports = router;