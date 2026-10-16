# 오스키실 예약판

오스키실 1–6번 방 시간표와 실습 재료 10종 × 2세트 대여 현황. 조원은 링크로 보기만, 신청·취소·재료 대여는 조장 코드로 로그인한 조장만.

주소: `https://minjoon1218.github.io/osce-board/`

## Supabase 세팅 (dw가 할 일)
1. supabase.com → 프로젝트 열기 (두근두근 치의학부 프로젝트에 같이 넣어도 됨, 테이블 이름 `bookings`·`kits`·`leaders`가 겹치지 않으면 OK)
2. **SQL Editor** → `schema.sql` 위쪽 6)번의 팀 목록 `array['A',...,'H']`을 실제 조에 맞게 고치고 → 전체 **Run**
3. 결과로 나오는 **조 / 조장 코드** 표를 각 조장에게 개인톡으로 전달 (코드는 단톡에 올리지 말 것)
4. **Project Settings → API** 에서 Project URL, `anon public` key 복사 → `index.html` 위쪽 `OSCE_CONFIG`에 넣고 커밋
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
