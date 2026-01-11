import { createContext, useState, useEffect, useContext } from 'react';

const CartContext = createContext();

export const useCart = () => useContext(CartContext);

export const CartProvider = ({ children }) => {
  // 1. Khởi tạo từ LocalStorage
  const [cartItems, setCartItems] = useState(() => {
    const savedCart = localStorage.getItem('muse_cart');
    return savedCart ? JSON.parse(savedCart) : [];
  });

  // 2. Sync với LocalStorage
  useEffect(() => {
    localStorage.setItem('muse_cart', JSON.stringify(cartItems));
  }, [cartItems]);

  // --- ACTIONS ---
  const addToCart = (product, variant, quantity) => {
    setCartItems(prev => {
      const existingItem = prev.find(item => item.variant_id === variant.id);
      if (existingItem) {
        return prev.map(item => item.variant_id === variant.id 
          ? { ...item, quantity: item.quantity + quantity } 
          : item);
      } else {
        return [...prev, {
          id: product.id, variant_id: variant.id,
          name: product.name, slug: product.slug, image: product.images?.[0],
          color: variant.color, size: variant.size, 
          price: Number(product.base_price), quantity: quantity
        }];
      }
    });
  };

  const removeFromCart = (variantId) => {
    setCartItems(prev => prev.filter(item => item.variant_id !== variantId));
  };

  const updateQuantity = (variantId, newQuantity) => {
    if (newQuantity < 1) return;
    setCartItems(prev => prev.map(item => item.variant_id === variantId ? { ...item, quantity: newQuantity } : item));
  };

  // QUAN TRỌNG: Hàm xóa sạch giỏ hàng
  const clearCart = () => {
    setCartItems([]);
    localStorage.removeItem('muse_cart');
  };

  const cartTotal = cartItems.reduce((total, item) => total + (item.price * item.quantity), 0);
  const cartCount = cartItems.reduce((count, item) => count + item.quantity, 0);

  return (
    <CartContext.Provider value={{ cartItems, addToCart, removeFromCart, updateQuantity, clearCart, cartTotal, cartCount }}>
      {children}
    </CartContext.Provider>
  );
};