import { createContext, useState, useEffect, useContext, useMemo } from 'react';
import { toast } from 'react-toastify';
const CartContext = createContext();

export const useCart = () => useContext(CartContext);

export const CartProvider = ({ children }) => {
  // 1. Khởi tạo & Làm sạch dữ liệu ngay lập tức
  const [cartItems, setCartItems] = useState(() => {
    try {
      const savedCart = localStorage.getItem('muse_cart');
      if (savedCart) {
        const parsed = JSON.parse(savedCart);
        // SANITIZE DATA: Ép kiểu số cho toàn bộ item khi vừa load lên
        // Khắc phục lỗi NaN
        return parsed.map(item => ({
          ...item,
          price: Number(item.price) || 0,
          quantity: Number(item.quantity) || 1,
          max_stock: Number(item.max_stock ?? 0) 
        }));
      }
    } catch (e) {
      console.error("Lỗi load cart:", e);
    }
    return [];
  });

  // 2. Sync với LocalStorage
  useEffect(() => {
    localStorage.setItem('muse_cart', JSON.stringify(cartItems));
  }, [cartItems]);

  // --- ACTIONS ---
  const addToCart = (product, variant, quantity = 1) => { // FIX: Mặc định quantity = 1
      setCartItems(prev => {
          const existingItem = prev.find(item => item.variant_id === variant.id);
          
          // Thông báo thành công
          toast.success(`Đã thêm "${product.name}" vào giỏ!`);

          if (existingItem) {
              return prev.map(item => 
                  item.variant_id === variant.id 
                      ? { ...item, quantity: item.quantity + Number(quantity) } 
                      : item
              );
          } else {
              return [...prev, {
                  product_id: product.id, 
                  variant_id: variant.id,
                  name: product.name, 
                  slug: product.slug, 
                  image: product.images?.[0] || '', 
                  color: variant.color, 
                  color_en: variant.color_en,
                  size: variant.size, 
                  price: Number(product.base_price),
                  quantity: Number(quantity), // FIX: Ép kiểu số
                  max_stock: Number(variant.quantity_remaining || 0)
              }];
          }
      });
  };

  const removeFromCart = (variantId) => {
    setCartItems(prev => prev.filter(item => item.variant_id !== variantId));
  };

  const updateQuantity = (variantId, newQuantity) => {
    if (newQuantity < 1) return;
    setCartItems(prev => prev.map(item => item.variant_id === variantId ? { ...item, quantity: Number(newQuantity) } : item));
  };

  const clearCart = () => {
    setCartItems([]);
    localStorage.removeItem('muse_cart');
  };

  // --- TÍNH TOÁN (Dùng useMemo để fix delay hiển thị trên Navbar) ---
  const cartTotal = useMemo(() => {
    return cartItems.reduce((total, item) => total + ((Number(item.price)||0) * (Number(item.quantity)||0)), 0);
  }, [cartItems]);

  const cartCount = useMemo(() => {
    return cartItems.reduce((count, item) => count + (Number(item.quantity)||0), 0);
  }, [cartItems]);

  return (
    <CartContext.Provider value={{ cartItems, addToCart, removeFromCart, updateQuantity, clearCart, cartTotal, cartCount }}>
      {children}
    </CartContext.Provider>
  );
};