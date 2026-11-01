# PicNest — Đề xuất thiết kế UI/UX tổng thể

**Trạng thái:** Concept để duyệt, chưa phải thiết kế triển khai.  
**Nền tảng:** macOS, một cửa sổ chính dạng native.  
**Định vị:** Quản lý và tổ chức ảnh riêng tư trên máy Mac; tạo nội dung nhẹ từ thư viện ảnh.

## Nguyên tắc thiết kế

1. **Local-first, tin cậy trước:** ảnh gốc không bị sửa hoặc xóa ngầm. Mọi hành động thay đổi file cho biết chính xác ảnh nào, ở đâu và có thể hoàn tác ra sao.
2. **Review nhanh, không bắt buộc hiểu AI:** AI đưa đề xuất; người dùng duyệt hoặc sửa. Confidence là tín hiệu hỗ trợ, không thay người dùng quyết định.
3. **Category khác Collection:** category điều khiển phân loại và có thể gắn với thư mục; collection chỉ là nhóm logic, không di chuyển file.
4. **Mỗi màn hình có một hành động chính:** Import, Review, Sort, Edit hoặc Export. Công cụ phụ nằm trong inspector, menu hoặc khu vực Tools.
5. **Dùng được với hàng nghìn ảnh:** tìm kiếm, lọc, multi-select, xử lý lô, thumbnail có thể điều chỉnh và trạng thái tác vụ dễ hiểu.

## Kiến trúc điều hướng

Cửa sổ chính chia thành sidebar, vùng làm việc và inspector tùy ngữ cảnh.

- **Library:** All Photos, Needs Review, Recently Added, Favorites.
- **Collections:** các nhóm do người dùng tạo, không làm thay đổi đường dẫn file.
- **Categories:** các nhóm phân loại có thể đồng bộ với folder, ví dụ Family, Food, Documents, Travel.
- **Tools:** Duplicates, Layouts, Export History.
- **Source folders:** lựa chọn thư mục nguồn/workspace đang làm việc; hiển thị tên folder và trạng thái quyền truy cập.

Trên toolbar: breadcrumb/tên workspace, search, sort/filter, điều chỉnh kích cỡ thumbnail, Undo, và hành động chính theo ngữ cảnh. Inspector có thể bật/tắt và thay đổi nội dung theo ảnh, category hoặc layout đang chọn.

## Các màn hình và luồng

### 1. Welcome / Workspaces

Màn hình đầu tiên có nút **Choose Folder…** và drop zone. Bên dưới là **Recent folders** dạng danh sách/card, hiển thị đường dẫn rút gọn, số ảnh, lần mở gần nhất và trạng thái như *Needs review* hoặc *Sorted*. Phiên chưa xong có nút **Continue**. Thông điệp riêng tư ngắn: *Your photos stay on this Mac.*

Khi mở folder có phiên trước, cho lựa chọn tiếp tục phiên hoặc **Start a new review**. Nếu thư mục đã bị di chuyển, đưa ra **Locate folder…**; không tự tạo phiên trống khác khiến người dùng tưởng dữ liệu mất.

### 2. Import / Scan

Sau khi chọn folder, hiển thị tên và đường dẫn, số ảnh đã tìm thấy, bộ lọc file được hỗ trợ, tiến độ scan/model, ước tính thời gian nếu có dữ liệu đáng tin cậy, và nút **Cancel**. Giải thích rõ Cancel không xóa cache hay ảnh nguồn. Nếu folder có video hoặc file không đọc được, gom vào mục riêng sau scan thay vì coi là lỗi tổng thể.

Kết thúc scan đưa người dùng vào Library/Review với summary: tổng ảnh, đề xuất category, số ảnh cần xem lại và số bản trùng tiềm năng. Nút chính **Review suggestions**.

### 3. Library / All Photos

Mặc định là grid ảnh với filter chip **All**, **Needs review**, **Edited by me**, **Favorites**. Có search theo tên file; sort theo ngày, tên, category hoặc confidence. Thumbnail hiển thị filename và ngày khi phù hợp. Confidence chỉ nổi bật với ảnh chưa chắc chắn; ảnh đã duyệt thủ công có badge *Reviewed* thay vì điểm AI.

Một click chọn ảnh; shift/command-click chọn nhiều ảnh. Double-click hoặc Space mở preview lớn. Drag ảnh vào category/collection theo đúng loại đích. Thanh selection xuất hiện khi có ảnh chọn, với **Move to…**, **Add to collection**, **Favorite**, **Reveal in Finder** và **More**. Các hành động destructive nằm riêng, không dùng chung nút chính.

### 4. Needs Review

Màn hình riêng cho những quyết định chưa chắc chắn. Có filter theo confidence thấp, không có đề xuất, đề xuất mâu thuẫn và nhóm ảnh tương tự. Mỗi ảnh có một đề xuất chính, lựa chọn thay thế, phần trăm confidence và lý do ngắn nếu model có giải thích phù hợp. Không hiển thị confidence như độ chính xác được đảm bảo.

Hành động theo ảnh: **Accept suggestion**, **Choose category…**, **Don't move**, hoặc **Not now**. Với nhiều ảnh có cùng best guess, người dùng có thể chọn nhóm và **Accept group**. Khi chấp nhận thủ công, đề xuất đó không bị tự đổi âm thầm ở lần rescan sau; thay đổi được đánh dấu *Chosen by you*.

### 5. Category và Collections

Tạo/đổi tên category hỏi rõ tên, icon và folder liên kết. Màn hình chi tiết cho biết đường dẫn folder; **Reveal in Finder** mở folder. Nếu category bị xóa, dialog phải ghi số ảnh sẽ chuyển vào Trash và folder có bị xóa hay không; luôn có **Cancel** và đường hoàn tác rõ ràng. Trước xóa nên cho xem preview danh sách ảnh bị ảnh hưởng.

Collection là nhóm logic độc lập: tạo, thêm/bỏ ảnh, đổi tên và xóa collection không đổi file/folder. Giao diện dùng icon hoặc nhãn riêng để phân biệt với category có folder. Không dùng cùng từ “category” cho cả hai hành vi.

### 6. Duplicates

Hai tab **Exact copies** và **Similar photos**. Mỗi cụm đặt ảnh cạnh nhau, thông tin kích thước và file size, lựa chọn **Keep** rõ ràng. Ảnh không được chọn giữ sẽ chỉ chuyển vào macOS Trash sau khi xác nhận hành động theo nhóm. Cho phép **Not duplicates** để bỏ đánh dấu một cụm. Hiển thị rõ số ảnh sẽ bị tác động trước **Clean up**; Undo hoặc khôi phục từ Trash cần nêu cụ thể.

### 7. Sort / Organize batch

Sheet xác nhận có đích lưu, chế độ **Copy** hoặc **Move**, tùy chọn tạo folder theo năm/tháng, quy tắc rename, và cách xử lý ảnh chưa chắc chắn. Trước khi chạy, preview cây thư mục/filename mẫu cùng số file dự kiến. Mặc định an toàn là Copy; Move cần thêm xác nhận giải thích nguồn sẽ thay đổi.

Trong lúc chạy: tiến độ theo số file, nút **Stop after current file**, thông báo file lỗi và không bỏ qua âm thầm. Khi hoàn tất: summary các file thành công/bỏ qua/lỗi, **Show in Finder** và **Undo Last Sort**.

### 8. Preview và chỉnh sửa nhẹ

Preview mở nhanh ở giữa giao diện, có next/previous, zoom, filename, metadata và category. Từ đây có thể mở **Edit**. Bản đầu chỉ cần crop, rotate, straighten và điều chỉnh exposure/contrast/warmth/saturation cơ bản.

Chỉnh sửa không phá hủy: file gốc không thay đổi. Người dùng xem trước kết quả và chọn **Export edited copy**. Luôn phân biệt Original và Edited copy; có Reset, Undo/Redo và ghi nhận thông số edit. Nếu nền tảng chưa hỗ trợ lưu edit recipe an toàn, chỉ cho export bản sao đã render thay vì tuyên bố edit không phá hủy.

### 9. Layouts

Từ category/collection hoặc lựa chọn ảnh, mở **Create Layout**. Bản đầu tập trung hai đầu ra: **Contact sheet** và **Collage**; có thể thêm Moodboard sau. Bố cục gồm panel ảnh có thể kéo-thả, canvas trung tâm, inspector layout với kích thước giấy/tỉ lệ, số cột, khoảng cách, nền và caption. Có Preview, Undo/Redo và autosave draft.

Export ra PNG/PDF hoặc định dạng đã được kiểm thử; chọn tên, nơi lưu và kích thước/chất lượng. Không thay thế ảnh gốc. Lưu layout thành dự án để chỉnh tiếp.

### 10. Settings / Privacy

Các mục: quyền truy cập folder, model trên thiết bị, xử lý cache, hành vi mặc định copy/move, quy tắc rename, ngôn ngữ, giao diện sáng/tối, shortcut và update. Nêu rõ dữ liệu nào được lưu cục bộ và có kết nối mạng nào (ví dụ kiểm tra phiên bản). Không đưa đồng bộ cloud vào mặc định; nếu thêm sau này cần opt-in tách biệt.

## Design system đề xuất

- **Phong cách:** native macOS, sáng làm mặc định; hỗ trợ dark mode theo system appearance.
- **Màu:** nền trung tính ấm, chữ than, accent berry/coral tiết chế; xanh cho trạng thái đã xác nhận; hổ phách cho cần xem; đỏ chỉ cho hành động destructive và lỗi nghiêm trọng.
- **Layout:** sidebar ổn định khoảng 220–250 pt; grid 3–6 cột tùy kích cỡ cửa sổ; inspector co giãn hoặc ẩn được. Không đóng đinh chiều rộng khiến ảnh quá nhỏ.
- **Hình ảnh:** bo góc vừa phải, viền chọn rõ, metadata phụ dưới thumbnail; tránh phủ nhiều badge và chữ lên ảnh.
- **Khả năng truy cập:** tương phản đủ, điều khiển bằng bàn phím, focus ring, VoiceOver labels, không dùng màu làm tín hiệu duy nhất, tôn trọng Reduce Motion.
- **Ngôn ngữ:** giữ tiếng Anh cho giao diện đầu theo đặc tả hiện tại; thiết kế chuỗi để có thể bản địa hóa tiếng Việt sau.

## Ưu tiên triển khai sau khi duyệt

1. **Foundation:** Library grid, search/filter, inspector, Needs Review, chọn nhiều ảnh, empty/error/loading states.
2. **Safety & organization:** category-folder confirmations, Collections tách khỏi Category, preview/undo tốt hơn, sort summary.
3. **Creation:** Contact Sheet, Collage, export và dự án layout.
4. **Light editor:** crop/rotate/adjust và export bản sao, sau khi xác nhận nhu cầu người dùng.

## Những điểm cần bạn duyệt

1. Có đồng ý giữ **Category = folder thật** và tạo **Collection = nhóm không di chuyển file** riêng không?
2. Màn hình chính nên mở vào **All Photos** hay **Needs Review** khi một phiên đang dở?
3. Muốn Layouts ưu tiên **Contact Sheet** hay **Collage** trước?
4. Chỉnh sửa chỉ xuất bản sao giữ nguyên gốc — có phù hợp định vị an toàn ảnh không?
5. Giữ UI tiếng Anh như bản hiện tại, hay thiết kế song ngữ Anh/Việt ngay từ đầu?
