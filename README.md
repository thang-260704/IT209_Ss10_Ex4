# Session 10 - Bài 4: Custom Network và Named Volume bằng Docker CLI

## 1. Mục tiêu

Dựng cụm 2 container bằng Docker CLI thủ công:

- **Backend** `app-container` (Express, image `hw-backend:v1` từ bài 2)
- **Database** `db-server` (`postgres:15-alpine`)

Hai container nằm chung **custom bridge network `app-net`** nên gọi nhau bằng tên container (DNS nội bộ của Docker). Dữ liệu PostgreSQL lưu trong **named volume `db-data`** nên vẫn còn sau khi container DB bị xoá và tạo lại.

## 2. Sơ đồ

```text
                      Host wean2607 :8084
                              │  -p 8084:3000
┌──────────────────── network: app-net (bridge) ─────────────────────┐
│                                                                    │
│   app-container (hw-backend:v1)          db-server (postgres:15)   │
│   DB_HOST=db-server  ──── DNS ────►      :5432 (không map ra host) │
│                                                │                   │
└────────────────────────────────────────────────┼───────────────────┘
                                                 │ -v db-data:/var/lib/postgresql/data
                                       Named Volume: db-data
                              (/var/lib/docker/volumes/db-data/_data)
```

## 3. Script `commands.sh`

File: [`commands.sh`](commands.sh). Chạy: `bash commands.sh`

| Bước | Lệnh chính | Mục đích |
|---|---|---|
| 0 | `docker rm -f`, `docker volume rm`, `docker network rm` | Dọn tài nguyên cũ để script chạy lại được nhiều lần |
| 1 | `docker network create --driver bridge app-net` | Tạo custom bridge network có DNS nội bộ |
| 2 | `docker volume create db-data` | Tạo named volume do Docker quản lý |
| 3 | `docker run -d --name db-server --network app-net -v db-data:/var/lib/postgresql/data … postgres:15-alpine` | Chạy DB, dữ liệu ghi vào volume; chờ `pg_isready` |
| 4 | `docker run -d --name app-container --network app-net -e DB_HOST=db-server … hw-backend:v1` | Chạy backend, truyền thông tin kết nối DB qua biến môi trường |
| 5 | `docker exec app-container ping -c 2 db-server` | Kiểm tra tên `db-server` được phân giải ra IP nội bộ |
| 6 | `CREATE TABLE students` + `INSERT` | Thêm dữ liệu mẫu |
| 7 | `docker rm -f db-server` | Xoá cứng container DB |
| 8 | Chạy lại `db-server` với cùng `-v db-data:…` | Tạo container DB hoàn toàn mới |
| 9 | `SELECT * FROM students` | Xác minh dữ liệu còn nguyên |

**Lưu ý:**

- `db-server` **không** map cổng 5432 ra host; chỉ container trong `app-net` mới truy cập được. Chỉ backend mới cần `-p 8084:3000`.
- Mật khẩu DB đọc từ biến `DB_PASS` (mặc định dùng cho bài tập); khi triển khai thật nên truyền qua biến môi trường hoặc file `.env`, không ghi cứng vào script.
- Mạng `bridge` mặc định của Docker **không** có DNS theo tên container; đó là lý do phải tạo network riêng.

## 4. Kết quả chạy script

```text
DB_NAME=appdb
DB_HOST=db-server
DB_USER=appuser

===== 5. Kiểm tra DNS nội bộ: app-container ping db-server =====
PING db-server (172.18.0.2): 56 data bytes
64 bytes from 172.18.0.2: seq=0 ttl=64 time=0.193 ms
64 bytes from 172.18.0.2: seq=1 ttl=64 time=0.114 ms

--- db-server ping statistics ---
2 packets transmitted, 2 packets received, 0% packet loss
round-trip min/avg/max = 0.114/0.153/0.193 ms
app-container => 172.18.0.3/16
db-server => 172.18.0.2/16

===== 6. Thêm dữ liệu vào DB =====
CREATE TABLE
INSERT 0 2
 id |        name        |   class
----+--------------------+------------
  1 | Nguyen Quyet Thang | IT209
  2 | Docker Volume      | Session 10
(2 rows)

===== 7. Xoá cứng container DB: docker rm -f db-server =====
db-server
Container db-server đã bị xoá
DRIVER    VOLUME NAME
local     db-data

===== 8. Khởi chạy lại container DB mới, gắn cùng volume db-data =====
4374d5b838b8bc8353f2cbb79a61220790ae600a43c4434e374442145e9a91fb
Chờ PostgreSQL sẵn sàng. OK

===== 9. Xác minh dữ liệu sau khi tái tạo container =====
 id |        name        |   class
----+--------------------+------------
  1 | Nguyen Quyet Thang | IT209
  2 | Docker Volume      | Session 10
(2 rows)

===== HOÀN TẤT =====
CONTAINER ID   IMAGE                COMMAND                  CREATED         STATUS         PORTS                                         NAMES
4374d5b838b8   postgres:15-alpine   "docker-entrypoint.s…"   2 seconds ago   Up 1 second    5432/tcp                                      db-server
0a4ba8dad113   hw-backend:v1        "docker-entrypoint.s…"   5 seconds ago   Up 4 seconds   0.0.0.0:8084->3000/tcp, [::]:8084->3000/tcp   app-container
```

**Phân tích:**

- **DNS nội bộ:** từ `app-container`, tên `db-server` được phân giải thành `172.18.0.2` (IP của DB trong mạng `app-net`, dải `172.18.0.0/16`); ping 2/2 gói, 0% loss.
- **Biến kết nối:** backend nhận `DB_HOST=db-server` thay vì địa chỉ IP, nên dù container DB được tạo lại và đổi IP, cấu hình vẫn đúng.
- **Data persistence:** bảng `students` có 2 dòng trước khi `docker rm -f db-server`. Container DB mới (ID `4374d5b838b8`) gắn lại `db-data` và `SELECT` trả về **đúng 2 dòng cũ**. Dữ liệu sống trong volume, không nằm trong lớp ghi của container.
- **Bảo mật cổng:** `db-server` chỉ hiện `5432/tcp` (không có `0.0.0.0:`), nghĩa là DB không mở ra ngoài host; chỉ `app-container` map cổng `8084`.

![Chạy commands.sh](images/01-run-script.png)

## 5. Kiểm tra theo yêu cầu

```bash
docker network ls | grep app-net
docker volume ls | grep db-data
docker network inspect app-net
docker exec -it app-container ping -c 2 db-server
```

Trích kết quả `docker network inspect app-net`:

```json
"Name": "app-net",
"Driver": "bridge",
"IPAM": { "Config": [ { "Subnet": "172.18.0.0/16", "Gateway": "172.18.0.1" } ] },
"Containers": {
    "0a4ba8dad113...": {
        "Name": "app-container",
        "MacAddress": "06:10:8b:d4:92:bd",
        "IPv4Address": "172.18.0.3/16"
    },
    "4374d5b838b8...": {
        "Name": "db-server",
        "MacAddress": "62:e2:b3:dc:25:79",
        "IPv4Address": "172.18.0.2/16"
    }
}
```

| Kiểm tra | Kết quả | Đạt |
|---|---|---|
| `app-net` tồn tại, driver `bridge` | Subnet `172.18.0.0/16`, gateway `172.18.0.1` | ✅ |
| `db-data` tồn tại | `local  db-data` (bước 7 của script) | ✅ |
| Cả 2 container cùng mạng | `app-container` = `172.18.0.3`, `db-server` = `172.18.0.2` | ✅ |
| `ping db-server` từ backend | Phân giải ra `172.18.0.2`, 2/2 gói, 0% loss | ✅ |
| Dữ liệu sau khi tái tạo container DB | 2 dòng vẫn còn nguyên | ✅ |

IP mà `ping` phân giải (`172.18.0.2`) trùng khớp với `IPv4Address` của `db-server` trong `network inspect`, chứng tỏ DNS nội bộ của Docker hoạt động đúng. Container ID `4374d5b838b8` là container DB **thứ hai** (tạo lại ở bước 8), xác nhận nó đã tham gia lại `app-net` thành công.

![docker network inspect app-net](images/02-network-inspect.png)

## 6. Kết luận

- Custom bridge network `app-net` cung cấp DNS nội bộ: backend gọi DB bằng tên `db-server`, không cần biết IP.
- Named volume `db-data` giữ dữ liệu PostgreSQL độc lập với vòng đời container: `docker rm -f` rồi tạo lại container DB mới, dữ liệu vẫn nguyên vẹn.
- Toàn bộ quy trình được tự động hoá trong `commands.sh`, chạy lại được nhiều lần cho kết quả giống nhau.
