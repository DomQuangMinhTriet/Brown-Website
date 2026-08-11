// server/config/supabase.js
const { createClient } = require('@supabase/supabase-js');
const path = require('path');
const dotenv = require('dotenv');

// Đảm bảo đường dẫn trỏ đúng về file .env ở thư mục cha
dotenv.config({ path: path.resolve(__dirname, '../.env') });

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_KEY;

// --- KIỂM TRA LỖI KẾT NỐI ---
if (!supabaseUrl || !supabaseKey) {
    console.error("❌ LỖI: Không tìm thấy biến môi trường trong file .env!");
    console.error("URL:", supabaseUrl);
    console.error("KEY:", supabaseKey ? "Đã có key" : "Chưa có key");
} else {
    console.log("✅ Config: Đã đọc được Supabase Key!");
}

// Tạo kết nối với quyền Service Role (Admin)
const supabase = createClient(supabaseUrl, supabaseKey, {
    auth: {
        persistSession: false, // Server không cần lưu session
        autoRefreshToken: false,
        detectSessionInUrl: false,
    }
});

module.exports = supabase;
