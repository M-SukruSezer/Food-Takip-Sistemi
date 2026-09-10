const express = require('express');
const authRoutes = require('./auth');
const storeRoutes = require('./stores');
const userRoutes = require('./users');
const productTypeRoutes = require('./productTypes');
const batchRoutes = require('./batches');
const recommendationRoutes = require('./recommendations');
const saleRoutes = require('./sales');
const dashboardRoutes = require('./dashboard');
const reportRoutes = require('./reports');
const logRoutes = require('./logs');
const approvalRoutes = require('./approvals');

const router = express.Router();

router.use('/auth', authRoutes);
router.use('/stores', storeRoutes);
router.use('/users', userRoutes);
router.use('/product-types', productTypeRoutes);
router.use('/batches', batchRoutes);
router.use('/recommendations', recommendationRoutes);
router.use('/sales', saleRoutes);
router.use('/dashboard', dashboardRoutes);
router.use('/reports', reportRoutes);
router.use('/logs', logRoutes);
router.use('/approvals', approvalRoutes);

module.exports = router;
