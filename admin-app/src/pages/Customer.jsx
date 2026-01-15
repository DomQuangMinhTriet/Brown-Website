import { useEffect, useState } from 'react';
import axios from 'axios';
import { FaUser, FaPhone, FaMapMarkerAlt, FaHistory } from 'react-icons/fa';

const Customers = () => {
  const [customers, setCustomers] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchCustomers = async () => {
      try {
        const res = await axios.get('http://localhost:5000/api/customers');
        if (res.data.success) setCustomers(res.data.data);
      } catch (error) {
        console.error(error);
      } finally {
        setLoading(false);
      }
    };
    fetchCustomers();
  }, []);

  return (
    <div className="p-6 md:p-10 max-w-7xl mx-auto">
      <h1 className="text-2xl font-bold text-stone-800 mb-6">Danh sách Khách hàng (CRM)</h1>
      
      <div className="bg-white rounded-xl border border-stone-200 shadow-sm overflow-hidden">
        <table className="w-full text-left">
          <thead className="bg-stone-50 text-stone-500 uppercase text-xs">
            <tr>
              <th className="p-4">Khách hàng</th>
              <th className="p-4">Liên hệ</th>
              <th className="p-4">Địa chỉ</th>
              <th className="p-4 text-center">Ngày tham gia</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-stone-100 text-sm">
            {customers.map(cus => (
              <tr key={cus.id} className="hover:bg-stone-50">
                <td className="p-4 font-medium text-stone-800 flex items-center gap-3">
                  <div className="w-8 h-8 rounded-full bg-stone-200 flex items-center justify-center text-stone-500">
                    <FaUser size={12}/>
                  </div>
                  {cus.full_name}
                </td>
                <td className="p-4 text-stone-600">
                  <div className="flex items-center gap-2"><FaPhone size={10}/> {cus.phone}</div>
                  <div className="text-xs text-stone-400 mt-1">{cus.email}</div>
                </td>
                <td className="p-4 text-stone-500 truncate max-w-xs">{cus.address}</td>
                <td className="p-4 text-center text-stone-400">
                  {new Date(cus.created_at).toLocaleDateString('vi-VN')}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {customers.length === 0 && !loading && (
            <div className="p-8 text-center text-stone-400">Chưa có dữ liệu khách hàng</div>
        )}
      </div>
    </div>
  );
};

export default Customers;