// server/controllers/shippingController.js
const { calculateShippingFee } = require('../services/shippingService');

exports.calculateFee = async (req, res) => {
    try {
        const { district, ward, weight } = req.body; 
        
        // Gọi service tính phí (Service này sẽ gọi API SPX hoặc fallback)
        const fee = await calculateShippingFee(district, ward, weight);

        res.json({ success: true, data: { fee } });
    } catch (error) {
        res.status(500).json({ success: false, message: error.message });
    }
};