-- Kiểm thử ràng buộc CSDL SmartCanteenDb: thử chèn/xóa dữ liệu SAI, mọi thao tác phải bị chặn.
-- Mỗi test chạy trong transaction riêng và được ROLLBACK, không làm thay đổi dữ liệu.
-- Yêu cầu: đã chạy POST /api/dev/seed và POST /api/dev/accounts.
-- Chạy: sqlcmd -S localhost -E -C -I -d SmartCanteenDb -f 65001 -i backend/sql/constraint-tests.sql
--   (cờ -I bật QUOTED_IDENTIFIER, bắt buộc với bảng có filtered index)

SET NOCOUNT ON;
DECLARE @uid nvarchar(128) = (SELECT TOP 1 Id FROM Users WHERE Role='Student');
DECLARE @cat int = (SELECT MIN(Id) FROM Categories);
DECLARE @food int = (SELECT MIN(Id) FROM Foods);
DECLARE @tests TABLE (n int IDENTITY, name nvarchar(80), sql nvarchar(max));
INSERT @tests(name, sql) VALUES
 (N'Giá món = 0',                    N'INSERT Foods(CategoryId,Name,Description,Price,PrepTimeMinutes,IsAvailable,AverageRating,RatingCount,IsDeleted) VALUES('+CAST(@cat AS nvarchar)+N',N''X'',N''x'',0,5,1,0,0,0)'),
 (N'Trùng tên món trong danh mục',   N'INSERT Foods(CategoryId,Name,Description,Price,PrepTimeMinutes,IsAvailable,AverageRating,RatingCount,IsDeleted) SELECT CategoryId,Name,N''x'',1000,5,1,0,0,0 FROM Foods WHERE Id='+CAST(@food AS nvarchar)),
 (N'Xóa danh mục còn món',           N'DELETE Categories WHERE Id='+CAST(@cat AS nvarchar)),
 (N'Voucher giảm 150%',              N'INSERT Vouchers(Code,Description,DiscountType,DiscountValue,MinOrderAmount,StartAt,EndAt,UsedCount,IsActive) VALUES(''BAD150'',N''x'',''Percent'',150,0,''2026-01-01'',''2026-12-31'',0,1)'),
 (N'Voucher EndAt < StartAt',        N'INSERT Vouchers(Code,Description,DiscountType,DiscountValue,MinOrderAmount,StartAt,EndAt,UsedCount,IsActive) VALUES(''BADDATE'',N''x'',''Fixed'',5000,0,''2026-12-31'',''2026-01-01'',0,1)'),
 (N'Trùng mã voucher',               N'INSERT Vouchers(Code,Description,DiscountType,DiscountValue,MinOrderAmount,StartAt,EndAt,UsedCount,IsActive) VALUES(''GIAM5K'',N''x'',''Fixed'',5000,0,''2026-01-01'',''2026-12-31'',0,1)'),
 (N'Tổng tiền sai (≠ tạm tính - giảm)', N'INSERT Orders(Id,PickupCode,UserId,Status,Subtotal,DiscountAmount,TotalAmount,PaymentMethod) VALUES(''o1'',''A01'','''+@uid+N''',''Received'',50000,5000,50000,''Cash'')'),
 (N'Giảm giá > tạm tính',            N'INSERT Orders(Id,PickupCode,UserId,Status,Subtotal,DiscountAmount,TotalAmount,PaymentMethod) VALUES(''o2'',''A02'','''+@uid+N''',''Received'',10000,20000,-10000,''Cash'')'),
 (N'Hủy đơn không có lý do',         N'INSERT Orders(Id,PickupCode,UserId,Status,Subtotal,DiscountAmount,TotalAmount,PaymentMethod) VALUES(''o3'',''A03'','''+@uid+N''',''Cancelled'',10000,0,10000,''Cash'')'),
 (N'Đơn của user không tồn tại',     N'INSERT Orders(Id,PickupCode,UserId,Status,Subtotal,DiscountAmount,TotalAmount,PaymentMethod) VALUES(''o4'',''A04'',''ghost'',''Received'',10000,0,10000,''Cash'')'),
 (N'LineTotal sai công thức',        N'INSERT Orders(Id,PickupCode,UserId,Status,Subtotal,DiscountAmount,TotalAmount,PaymentMethod) VALUES(''ok1'',''B01'','''+@uid+N''',''Received'',10000,0,10000,''Cash''); INSERT OrderItems(OrderId,FoodId,FoodName,UnitPrice,OptionsPrice,Quantity,LineTotal) VALUES(''ok1'','+CAST(@food AS nvarchar)+N',N''x'',10000,0,2,10000)'),
 (N'Số lượng = 0',                   N'INSERT Orders(Id,PickupCode,UserId,Status,Subtotal,DiscountAmount,TotalAmount,PaymentMethod) VALUES(''ok2'',''B02'','''+@uid+N''',''Received'',10000,0,10000,''Cash''); INSERT OrderItems(OrderId,FoodId,FoodName,UnitPrice,OptionsPrice,Quantity,LineTotal) VALUES(''ok2'','+CAST(@food AS nvarchar)+N',N''x'',10000,0,0,0)'),
 (N'Đánh giá 6 sao',                 N'INSERT Orders(Id,PickupCode,UserId,Status,Subtotal,DiscountAmount,TotalAmount,PaymentMethod) VALUES(''ok3'',''B03'','''+@uid+N''',''Completed'',10000,0,10000,''Cash''); INSERT Reviews(UserId,FoodId,OrderId,Rating) VALUES('''+@uid+N''','+CAST(@food AS nvarchar)+N',''ok3'',6)'),
 (N'Đánh giá 1 món 2 lần / 1 đơn',   N'INSERT Orders(Id,PickupCode,UserId,Status,Subtotal,DiscountAmount,TotalAmount,PaymentMethod) VALUES(''ok4'',''B04'','''+@uid+N''',''Completed'',10000,0,10000,''Cash''); INSERT Reviews(UserId,FoodId,OrderId,Rating) VALUES('''+@uid+N''','+CAST(@food AS nvarchar)+N',''ok4'',5),('''+@uid+N''','+CAST(@food AS nvarchar)+N',''ok4'',4)'),
 (N'Yêu thích trùng',                N'INSERT Favorites(UserId,FoodId) VALUES('''+@uid+N''','+CAST(@food AS nvarchar)+N'),('''+@uid+N''','+CAST(@food AS nvarchar)+N')'),
 (N'Thanh toán Paid thiếu PaidAt',   N'INSERT Orders(Id,PickupCode,UserId,Status,Subtotal,DiscountAmount,TotalAmount,PaymentMethod) VALUES(''ok5'',''B05'','''+@uid+N''',''Received'',10000,0,10000,''Cash''); INSERT Payments(OrderId,Method,Amount,Status) VALUES(''ok5'',''Cash'',10000,''Paid'')'),
 (N'Trùng mã sinh viên',             N'INSERT Users(Id,Email,FullName,StudentCode,Role,IsActive) VALUES(''dup'',''dup@x.vn'',N''x'',''0023410001'',''Student'',1)'),
 (N'Email sai định dạng',            N'INSERT Users(Id,Email,FullName,Role,IsActive) VALUES(''bad'',''khongphaiemail'',N''x'',''Student'',1)'),
 (N'Nhóm bắt buộc nhưng MinSelect=0',N'INSERT FoodOptionGroups(FoodId,Name,IsRequired,MinSelect,MaxSelect,SortOrder) VALUES('+CAST(@food AS nvarchar)+N',N''Bad'',1,0,1,9)');
DECLARE @i int = 1, @max int = (SELECT MAX(n) FROM @tests), @name nvarchar(80), @sql nvarchar(max);
WHILE @i <= @max BEGIN
  SELECT @name = name, @sql = sql FROM @tests WHERE n = @i;
  BEGIN TRAN;
  BEGIN TRY EXEC sp_executesql @sql; PRINT N'❌ KHÔNG CHẶN  | ' + @name; END TRY
  BEGIN CATCH PRINT N'✅ Chặn  | ' + @name + N'  → ' + LEFT(ERROR_MESSAGE(), 70); END CATCH
  IF @@TRANCOUNT > 0 ROLLBACK;
  SET @i += 1;
END
