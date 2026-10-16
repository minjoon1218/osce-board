# 오스키실 예약판

오스키실 1–6번 방 시간표와 실습 재료 10종 × 2세트 대여 현황. 조원은 링크로 보기만, 신청·취소·재료 대여는 조장 코드로 로그인한 조장만.

주소
- 예약판 (조장 신청): `https://osce-board.vercel.app/`
- 현황판 (누구나 보기, 실시간): `https://osce-board.vercel.app/view.html`

Supabase 주소·키는 `config.js` 한 곳에만 있고 두 페이지가 같이 씀.
배포: Vercel이 `main` 브랜치에 push될 때마다 자동 배포 (GitHub Pages는 사용 안 함).

## Supabase 세팅 (dw가 할 일)
1. supabase.com → 프로젝트 열기 (두근두근 치의학부 프로젝트에 같이 넣어도 됨, 테이블 이름 `bookings`·`kits`·`leaders`가 겹치지 않으면 OK)
2. **SQL Editor** → `schema.sql` 위쪽 6)번의 팀 목록 `array['A',...,'H']`을 실제 조에 맞게 고치고 → 전체 **Run**
3. 결과로 나오는 **조 / 조장 코드** 표를 각 조장에게 개인톡으로 전달 (코드는 단톡에 올리지 말 것)
4. **Project Settings → API** 에서 Project URL, `anon public` key 복사 → `config.js`에 넣고 커밋
   - GitHub 웹에서 파일 열고 연필(✏️) 눌러 수정 → Commit changes
   - `service_role` 키는 절대 넣지 말 것

## 권한 구조
| | 조원 (로그인 X) | 조장 (코드 로그인) |
|---|---|---|
| 시간표·재료 현황 보기 | O | O |
| 연습 신청 | X | O (우리 조로만) |
| 신청 취소 | X | 우리 조 신청만 |
| 재료 대여·반납 | X | O |

모든 쓰기는 DB 함수(`create_booking`, `cancel_booking`, `set_kit`)에서 조장 코드를 확인한 뒤에만 됨. `leaders` 테이블은 아무도 직접 못 읽음.

## DB가 막아주는 것
- 같은 날·같은 방·겹치는 시간 → 거부
- 같은 조가 같은 시간에 방 두 개 → 거부
- 같은 재료 세트를 겹치는 시간에 → 거부
- 사용 시간은 1시간 또는 2시간만

## 자주 쓰는 SQL
```sql
-- 조장 코드 재발급 (조장 바뀔 때)
update leaders set code = upper(substr(md5(random()::text),1,6)) where team = 'C';
select team, code from leaders order by team;
-- 조 추가
insert into leaders (team, code) values ('I', upper(substr(md5(random()::text),1,6)));
-- 지난 예약 정리
delete from bookings where date < current_date - 30;
```

## 수정 포인트 (`index.html` 스크립트 맨 위)
`ROOMS`(방), `KITS`(재료), `DURS`(사용 시간), `OPEN`/`CLOSE`(운영 시간). 재료를 추가하면 `kits` 테이블에도 `id` 두 줄(예: `xray-1`, `xray-2`) 추가.

## 단톡 공지 문구
```
📌 오스키실 예약 안내
현황 보기 (누구나): https://osce-board.vercel.app/view.html
신청하기 (조장): https://osce-board.vercel.app/
- 조원은 현황판에서 방·시간·재료 확인
- 신청·취소·재료 대여는 조장이 받은 코드로 로그인해서
- 재료 꺼낼 때 '대여', 넣을 때 '반납' 꼭 눌러주세요
```

## 업데이트 002: 관리자·공지·방 관리·예약 기간
Supabase SQL Editor에서 `migrations/002_admin.sql` 실행 → 결과로 나오는 **관리자 코드** 보관.
- 관리자 코드로 로그인(예약판 '로그인')하면: 공지 수정, 방별 사용 가능/불가·토마스 있음/없음·메모, 모든 조 신청 취소, 조 지정 대리 신청(날짜 제한 없음), 재료 대여·반납
- 조장 신청은 **오늘~2일 후**까지만, 매일 **밤 10시**에 다음 날짜 오픈 (DB에서도 막음)
- 현황판 방 칸에 토마스 여부와 사용 중인 재료 세트 표시

## 업데이트 003: 조당 하루 2회
Supabase SQL Editor에서 `migrations/003_daily_limit.sql` 실행.
- 조장은 같은 날짜에 최대 2회까지 신청 (DB에서도 막음). 관리자 대리 신청은 제한 없음

## 업데이트 004: 오스키실 전체 사용 금지
Supabase SQL Editor에서 `migrations/004_blocks.sql` 실행.
- 관리자 메뉴 → '오스키실 전체 사용 금지'에서 날짜·시간·사유 입력 → 그 시간엔 1–6번 방 모두 조장 신청 불가 (DB에서도 막음)
- '겹치는 신청도 같이 취소'를 켜면 그 시간과 겹치는 기존 신청을 한 번에 취소
- 예약판·현황판 상단에 빨간 '전체 사용 금지' 공지로 자동 표시, 시간표엔 빗금 띠
- 목록에서 '삭제'를 누르면 바로 해제
