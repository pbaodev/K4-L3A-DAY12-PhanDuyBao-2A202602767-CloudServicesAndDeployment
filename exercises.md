# Phiếu Phản Ánh — K4 Level 3A, Ngày 12

> **Bài làm cá nhân.** Trả lời bằng lời của chính bạn, dựa trên những gì bạn
> quan sát được khi chạy code — không sao chép đáp án của người khác.
>
> Cách trả lời: thay dòng placeholder dưới mỗi câu hỏi bằng câu trả lời.
> `grade.py` đếm số câu đã trả lời (15 điểm cho 10 câu).
>
> Họ và tên: Phan Duy Bao  Mã học viên: 2A202602767

---

### Câu 1 — Fail fast (CP1)

Trong `Settings`, `agent_api_key` không có giá trị mặc định nên app chết ngay
khi khởi động nếu thiếu biến môi trường. Hãy mô tả một tình huống cụ thể mà
việc "chết sớm" này cứu bạn, so với việc để mặc định `"changeme"`.

Tình huống: lúc deploy lên Railway, service `day12-agent` được tạo rỗng và
biến phải set riêng ở bước sau. Nếu mình quên set `AGENT_API_KEY` mà code có
mặc định `"changeme"`, container vẫn khởi động, `/health` vẫn trả 200, Railway
báo deploy SUCCESS — nhìn bề ngoài mọi thứ đều xanh. Nhưng URL là public, và
`"changeme"` là chuỗi ai cũng đoán được (nó nằm luôn trong repo public), nên
bất kỳ ai cũng gọi được `/ask` và đốt ngân sách LLM của mình. Mình chỉ phát
hiện khi thấy hóa đơn.

Không có mặc định thì `Settings()` ném `ValidationError` ngay lúc khởi động,
container chết trước khi nhận request nào, healthcheck của Railway fail và
deploy bị đánh dấu thất bại. Lỗi hiện ra **lúc deploy, trong log**, thay vì
hiện ra **sau vài ngày, trên hóa đơn**. Test `test_thieu_api_key_thi_fail_fast`
kiểm tra đúng hành vi này.

---

### Câu 2 — Log cho máy đọc (CP1)

Chạy service và gọi `/ask` vài lần. Dán một dòng log JSON bạn thu được, rồi
nêu **hai** việc bạn làm được với dòng log đó mà `print("đã trả lời xong")`
không làm được.

Một dòng log thật khi chạy stack bằng docker compose:

```
{"event": "ask_completed", "level": "info", "timestamp": "2026-09-28T12:53:35.992390+00:00", "user_id": "sv-rl", "tokens_in": 392, "tokens_out": 43, "cost_usd": 8.46e-05}
```

Hai việc làm được mà `print("đã trả lời xong")` không làm được:

1. **Lọc và đếm theo trường.** Mình đã dùng chính log này để biết request
   nào rơi vào container nào: `docker compose logs agent | grep sv-scale`
   cho ra agent-1: 2, agent-2: 2, agent-3: 1. Trên Railway/Datadog có thể
   query kiểu `event = "ask_completed" AND user_id = "sv-rl"` mà không phải
   viết regex bóc chữ.
2. **Tính tổng và cảnh báo.** Vì `cost_usd`, `tokens_in`, `tokens_out` là số,
   hệ thống log có thể cộng chi phí theo user/giờ, vẽ biểu đồ token, hoặc bắn
   cảnh báo khi chi phí một user tăng đột biến. Câu `print` không có user,
   không có số, không có thời điểm chuẩn ISO để sắp xếp log giữa nhiều
   container.

---

### Câu 3 — Kích thước image (CP2)

Build cả hai phiên bản và ghi lại số đo thật:

```bash
docker build -f <Dockerfile-1-stage> -t agent:single .
docker build -t agent:multi .
docker images | grep agent
```

| Bản | Dung lượng |
|-----|-----------|
| 1 stage (bản đầu) | ... MB |
| Multi-stage | ... MB |

Giải thích: phần dung lượng chênh lệch đó là những gì?

| Bản | Dung lượng |
|-----|-----------|
| 1 stage (bản đầu, `FROM python:3.11`) | 1.73 GB |
| Multi-stage (`python:3.11-slim`) | 335 MB |

Chênh lệch ~1.4 GB. Mình xem `docker history` để biết nó là gì:

- Layer `pip install` ở cả hai bản gần như bằng nhau (~95 MB ở bản 1 stage,
  venv copy sang ~96 MB ở bản multi-stage). Tức là **thư viện của app không
  phải nguyên nhân**.
- Phần chênh gần như toàn bộ nằm ở **base image**: `python:3.11` bản đầy đủ
  dựa trên Debian đầy đủ, mang theo bộ công cụ build và dev. Mình chạy
  `which gcc make git` trong image 1 stage thì có đủ cả ba, còn image
  multi-stage thì không có cái nào. Thêm header, thư viện `-dev`, tài liệu…
  những thứ chỉ cần khi *biên dịch*, không cần khi *chạy*.

Nhận xét thêm: với lab này dependency toàn là wheel có sẵn, nên phần lớn lợi
ích đến từ việc đổi sang base `slim`. Multi-stage sẽ phát huy rõ hơn khi có
package phải compile (cần gcc ở stage builder, rồi bỏ gcc lại ở stage
runtime). Ngoài dung lượng, image nhỏ còn ít công cụ hơn cho kẻ tấn công lợi
dụng (không có gcc, git) và pull/deploy nhanh hơn.

---

### Câu 4 — Thứ tự lệnh trong Dockerfile (CP2)

Sửa một ký tự trong `app/main.py` rồi build lại. Với Dockerfile của bạn, những
layer nào được dùng lại từ cache, layer nào phải chạy lại? Nếu bạn đặt
`COPY . .` lên trước `RUN pip install` thì kết quả khác thế nào?

Mình thêm một dòng comment vào `app/main.py` rồi build lại. Kết quả thật
từ `docker build --progress=plain`:

- **Dùng lại cache (CACHED):** `RUN python -m venv`, `COPY requirements.txt`,
  `RUN pip install`, `RUN groupadd/useradd`, `WORKDIR`,
  `COPY --from=builder /opt/venv`.
- **Chạy lại:** `COPY app/ ./app/` và `COPY utils/ ./utils/` (layer nằm sau
  một layer đã đổi thì cũng phải làm lại). Hai bước này chỉ copy vài trăm KB
  nên gần như tức thì.

Với Dockerfile gốc đặt `COPY . .` **trước** `RUN pip install`, mình build lại
sau cùng thay đổi đó: `COPY . .` chạy lại (vì nội dung thư mục đổi) và kéo
theo `RUN pip install` **chạy lại toàn bộ**, cả lần build mất ~18 giây dù
`requirements.txt` không đổi một chữ. Docker cache theo chuỗi: một layer đổi
thì mọi layer phía sau đều mất cache. Vì vậy phải đặt thứ ít thay đổi nhất
(danh sách thư viện) lên trước, thứ đổi liên tục (source code) xuống cuối.

---

### Câu 5 — Vì sao không chạy bằng root (CP2)

Container mặc định chạy bằng root. Mô tả chuỗi sự kiện dẫn từ "một lỗ hổng
trong code Python của bạn" tới "kẻ tấn công có quyền cao trên máy host", và
lệnh `USER` cắt đứt chuỗi đó ở chỗ nào.

Chuỗi sự kiện khi container chạy bằng root:

1. Code Python có lỗ hổng, ví dụ một endpoint vô tình `eval` input, hoặc một
   thư viện dính lỗi deserialize → kẻ tấn công **chạy được lệnh** trong
   container.
2. Lệnh đó chạy với quyền của process: **root (uid 0)**. Kẻ tấn công đọc được
   mọi file trong container, cài thêm công cụ bằng `apt`, sửa code app.
3. Container không phải máy ảo — nó dùng chung kernel với host, và uid 0
   trong container cũng là uid 0 trên host (nếu không bật user namespace).
   Chỉ cần thêm một cấu hình lỏng (mount `/var/run/docker.sock`, mount thư
   mục host, `--privileged`) hoặc một lỗ hổng kernel/runtime để thoát
   container là kẻ tấn công **thành root trên máy host**, điều khiển được mọi
   container khác.

`USER app` cắt chuỗi ở **bước 2**: mình kiểm tra `docker compose exec agent id`
ra `uid=999(app) gid=999(app)`. Dù bị chiếm quyền chạy lệnh ở bước 1, kẻ tấn
công chỉ là user thường: không cài được package, không ghi được vào thư mục hệ
thống, và nếu có thoát ra host thì cũng chỉ là một uid không có đặc quyền —
bước 3 khó hơn rất nhiều.

---

### Câu 6 — Cửa sổ trượt (CP3)

Rate limit của bạn dùng sliding window 60 giây. Nếu thay bằng cách đếm theo
phút đồng hồ (reset lúc giây 00), một người dùng có thể gửi tối đa bao nhiêu
request trong 2 giây liên tiếp khi hạn mức là 10/phút? Giải thích cách đạt được
con số đó.

Tối đa **20 request trong 2 giây**.

Cách đạt được với hạn mức 10/phút, đếm theo phút đồng hồ:

- Lúc 10:00:59 gửi 10 request → bộ đếm phút 10:00 là 10/10, hợp lệ.
- Lúc 10:01:00 bộ đếm reset về 0.
- Trong giây 10:01:00 gửi tiếp 10 request → bộ đếm phút 10:01 là 10/10,
  vẫn hợp lệ.

Tổng cộng 20 request trong khoảng 2 giây, gấp đôi hạn mức mà không vi phạm
luật nào. Với sliding window, lúc 10:01:00 mình đếm các request trong 60 giây
gần nhất (từ 10:00:00), vẫn thấy 10 request lúc 10:00:59 nên request thứ 11
bị chặn 429. Lúc test thật trên Railway, 15 request liên tiếp cho ra đúng
`200 ×10` rồi `429 ×5`.

---

### Câu 7 — Rate limit và cost guard (CP3)

Hai cơ chế này khác nhau ở điểm nào? Cho một tình huống mà rate limit cho qua
nhưng cost guard phải chặn, và một tình huống ngược lại.

Khác nhau ở **đơn vị đo**: rate limit đếm *số request* trong 60 giây gần
nhất (chống spam/burst, trả 429 và bảo client thử lại sau `Retry-After`).
Cost guard cộng *số tiền* đã tiêu trong cả tháng (chống cháy ngân sách, trả
402 và chỉ hết khi sang tháng mới).

- **Rate limit cho qua nhưng cost guard chặn:** một user gửi đều đặn
  5 request/phút — luôn dưới 10/phút — nhưng mỗi câu hỏi dán vào cả một tài
  liệu dài 50k token. Sau vài ngày chạy liên tục, tổng chi phí vượt
  10 USD/tháng → 402, dù chưa lần nào bị 429.
- **Cost guard cho qua nhưng rate limit chặn:** một script lỗi gọi `/ask`
  vòng lặp 15 lần trong 1 giây với câu hỏi ngắn "test". Mỗi lần chỉ tốn
  ~0.00008 USD nên ngân sách còn gần như nguyên, nhưng từ request thứ 11 đã
  bị 429 — đúng như mình quan sát khi test.

---

### Câu 8 — /health khác /ready (CP4)

Nếu gộp hai endpoint làm một và cho nó kiểm tra Redis, chuyện gì xảy ra với cụm
3 container khi Redis mất kết nối 30 giây? Trả lời theo đúng thứ tự sự kiện.

Giả sử cụm 3 container, endpoint gộp dùng cho **cả** liveness lẫn
readiness và có ping Redis. Redis mất kết nối 30 giây:

1. **t = 0s:** Redis mất kết nối. Cả 3 container cùng lúc trả 503 cho
   endpoint gộp (vì cùng dùng một Redis).
2. **Load balancer** thấy cả 3 không ready → rút cả 3 khỏi vòng xoay → mọi
   request của user nhận 502/503. (Đến đây là hợp lý: không có Redis thì
   thật sự không phục vụ được.)
3. **Orchestrator** dùng cùng endpoint làm liveness, thấy fail liên tiếp vài
   lần (vd. 3 lần × 10s) → kết luận process "chết" → **restart cả 3
   container**, dù process Python hoàn toàn khỏe. Request đang xử lý dở bị
   cắt ngang.
4. Container mới khởi động trong lúc Redis vẫn chưa về → probe tiếp tục fail
   → bị restart tiếp, rơi vào vòng lặp restart có backoff (thời gian chờ
   giữa các lần restart tăng dần).
5. **t = 30s:** Redis sống lại, nhưng container đang ở giữa chu kỳ restart /
   backoff nên phải chờ thêm → thời gian sập kéo dài **lâu hơn 30 giây**, và
   lỗi của một dependency đã biến thành sự cố của cả cụm.

Tách ra thì: `/health` (không đụng Redis) vẫn 200 nên không container nào bị
restart; chỉ `/ready` trả 503 để LB tạm ngừng gửi traffic. Redis về là `/ready`
200 lại ngay, hồi phục trong vài giây.

---

### Câu 9 — Stateless (CP4)

Chạy `docker compose up --scale agent=3` rồi gọi `/ask` nhiều lần với cùng một
`X-User-Id`. Quan sát `history_length` trong response. Nếu lịch sử được lưu
trong một dict Python thay vì Redis, bạn sẽ thấy con số đó thay đổi thế nào?

Mình chạy `docker compose --profile lb up -d --scale agent=3` (3 agent sau
nginx round-robin) rồi gọi `/ask` 5 lần với cùng `X-User-Id: sv-scale`.
Kết quả thật:

```
history_length = 0, 2, 4, 6, 8
```

Log cho thấy 5 request đó được xử lý bởi agent-1 (2 lần), agent-2 (2 lần),
agent-3 (1 lần) — tức là request liên tiếp **nhảy qua lại giữa các
container**, nhưng lịch sử vẫn tăng đều vì cả 3 cùng đọc/ghi một Redis.

Nếu lưu trong dict Python, mỗi container có dict riêng trong RAM của nó. Con
số sẽ **không tăng đều mà nhảy lung tung**: lần đầu gặp user ở container nào
thì container đó thấy 0; lần sau rơi lại vào container đã từng gặp user thì
thấy 2, rơi vào container chưa gặp thì lại 0. Với round-robin qua 3 container
sẽ ra kiểu `0, 0, 0, 2, 2` thay vì `0, 2, 4, 6, 8` — agent "mất trí nhớ"
tùy theo request rơi vào đâu. Và khi container restart (deploy bản mới),
toàn bộ lịch sử trong dict mất sạch.

---

### Câu 10 — Deploy thật (CP5)

Ghi lại **một** lỗi bạn gặp khi deploy lên cloud (build fail, health check
timeout, sai REDIS_URL, app không đọc `$PORT`...): thông báo lỗi là gì, bạn
tìm ra nguyên nhân bằng cách nào, và sửa ra sao?

Bản deploy lên Railway thành công ngay lần đầu (`railway deployment list`
chỉ có 1 deployment, trạng thái SUCCESS), nhờ đã xử lý trước một lỗi phát
hiện khi đọc `railway.toml`:

- **Lỗi:** file cấu hình có sẵn
  `startCommand = "uvicorn app.main:app --host 0.0.0.0 --port $PORT"`.
  `startCommand` của Railway không chạy qua shell, nên `$PORT` không được
  thay giá trị — uvicorn sẽ nhận nguyên chuỗi `"$PORT"`, báo port không phải
  số nguyên và thoát, healthcheck `/health` timeout.
- **Cách tìm ra:** so sánh với Dockerfile — ở đó phải dùng
  `CMD ["sh", "-c", "exec uvicorn ... --port ${PORT:-8000}"]` chính vì dạng
  exec (JSON array) không expand biến. `startCommand` gặp đúng vấn đề đó.
- **Cách sửa:** bỏ `startCommand` khỏi `railway.toml` để Railway dùng `CMD`
  của Dockerfile (chạy qua `sh -c`, có `exec` để uvicorn là PID 1 và nhận
  SIGTERM).

Một lỗi thật khác gặp khi chạy stack ở máy: `docker compose --profile lb up`
báo `Bind for 0.0.0.0:8080 failed: port is already allocated` vì cổng 8080
đang bị container khác chiếm. Mình kiểm tra bằng `lsof -iTCP:8080` rồi đổi
nginx sang `${LB_PORT:-8088}:80`. Ngoài ra Railway CLI cảnh báo `railway.toml`
(Config as Code) sẽ ngừng hỗ trợ từ 2026-12-01 — cần migrate sang
Infrastructure as Code nếu dùng lâu dài.
