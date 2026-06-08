# Modoc AI Pipeline — KPI Rating & Weekly Snapshot Form  
# Modoc AI 파이프라인 — KPI 평가 및 주간 스냅샷 양식

**Version:** 1.0 · **Kickoff baseline:** TBD · **Target KPI:** TBD (CEO sign-off at kickoff)

---

## Quick reference | 요약

| | English | 한국어 |
|---|---------|--------|
| **Main KPI** | Σ Views (all platforms) ÷ Σ Pipeline human execution time (incl. medical review) | Σ 조회수 (전 플랫폼) ÷ Σ 파이프라인 인간 작업 시간 (의학 리뷰 포함) |
| **Goal** | Minimize human time per published video = maximize automation | 편당 사람 개입 시간 최소화 = 자동화 수준 극대화 |
| **Achievement KPI** | **Peak** weekly snapshot value during the project (Rule 5) | 프로젝트 기간 **주간 스냅샷 중 최댓값** (규칙 5) |
| **KPI starts** | After end-to-end pipeline completes ≥1 time (Rule 3) | End-to-end 파이프라인 1회 완성 후 (규칙 3) |
| **Snapshots** | Every Monday at weekly review (Rule 4) | 매주 월요일 주간 리뷰 시 (규칙 4) |

---

# PART A — ENGLISH

---

## 1. Time classification (read before logging)

| Type | Examples | Include in KPI denominator? |
|------|----------|----------------------------|
| **Internship time** (13-week fixed resource) | System dev, pipeline design, learning, debugging, meetings, research, brainstorming, failed experiments | **No** |
| **Pipeline execution time** (KPI denominator) | Repeat human intervention from source selection → publish for one video (incl. medical review for EN/KO/ES) | **Yes** |

> We measure **how automated the pipeline is**, not how many hours you spent building it.

---

## 2. Per-video pipeline time log

*One row per published video (medical review **Pass** only). Sum these rows for weekly KPI.*

**Video ID / title:** ________________________________  
**Publish date:** __________ **Pipeline format:** ☐ A (Q&A) ☐ B (Newsletter) ☐ C (Meme/trend) ☐ Other: ______  
**Languages published:** ☐ EN ☐ KO ☐ ES  
**Platforms:** ☐ YouTube ☐ MoDoc blog ☐ Instagram ☐ Facebook  

| Stage | Owner | Minutes | Notes |
|-------|-------|---------|-------|
| 1. Content selection & extraction | Intern team | | |
| 2. Format decision / routing | Intern / AI router | | |
| 3. Video production | Intern / pipeline | | Baseline (prod only): median **45 min**, mean **53 min** |
| 4. Medical review (all languages) | MC + Dr. Sam | | Ref: EN ~1 min/vid, KO ~1 min/vid, ES ~10 min/vid (5-video sample) |
| 5. Upload & publish (all channels) | PM | | YouTube + blog embed + IG + FB |
| **Total pipeline execution time** | | **____ min** | **KPI denominator for this video** |

**Logged by:** ________________ **Date:** __________

---

## 3. Weekly views log

*Sum views across all platforms for videos published in the tracking period.*

| Video ID | Publish date | YouTube | MoDoc blog | Instagram | Facebook | **Row total** |
|----------|--------------|---------|------------|-----------|------------|---------------|
| | | | | | | |
| | | | | | | |
| | | | | | | |
| **Weekly Σ views** | | | | | | **________** |

---

## 4. Weekly KPI snapshot (every Monday)

**Week #:** ____ **Snapshot date (Mon):** __________  
**E2E pipeline operational?** ☐ Yes (KPI tracking active) ☐ No (Rule 3 — do not score yet)

| Metric | This week | Cumulative (project-to-date) |
|--------|-----------|------------------------------|
| Σ Views (all platforms) | | |
| Σ Pipeline execution time (min) | | |
| **Weekly KPI** = Σ Views ÷ Σ Time (hrs) | **________ views/hr** | **________ views/hr** |
| Videos published (review Pass) | | |
| Interns contributing | | |

**Peak KPI to date (Rule 5):** __________ views/hr · **Week achieved:** ______

**Notes (automation wins, bottlenecks, experiments):**

```
```

**Prepared by:** ________________ **Reviewed by (CEO/PM):** ________________

---

## 5. KPI rating scale

*Rate the **cumulative peak KPI** against baseline and kickoff target. CEO may adjust tiers at kickoff.*

| Rating | Label | Criteria (views per hour of pipeline execution time) |
|--------|-------|-----------------------------------------------------|
| ☐ **5 — Exceptional** | Peak KPI ≥ **150%** of kickoff target | |
| ☐ **4 — Strong** | Peak KPI ≥ **100%** of kickoff target | |
| ☐ **3 — On track** | Peak KPI ≥ **100%** of baseline composite | |
| ☐ **2 — Below baseline** | Peak KPI ≥ **50%** of baseline composite | |
| ☐ **1 — Needs intervention** | Peak KPI < **50%** of baseline composite | |

**Baseline composite (TBD at kickoff):**

```
Per-video pipeline time = selection + format + production + medical review + publish
Baseline production-only (measured): median 45 min · mean 53 min · range 25–100 min
Full baseline per video: __________ min (TBD)
Baseline KPI (views/hr): __________ (TBD after first publish + view window agreed with CEO)
Kickoff target KPI: __________ views/hr
```

**Final achievement KPI (end of project):** __________ views/hr · **Rating:** ☐ 1 ☐ 2 ☐ 3 ☐ 4 ☐ 5

---

## 6. Output & quality gates (reference — not the main KPI)

| Item | Target | This week |
|------|--------|-----------|
| Publish volume | **3 videos / intern / week** (Pass only) | |
| Team capacity example | 6 interns × 3 sources × 3 languages = **54 pieces** (baseline reference) | |
| Medical review | **Pass required** before publish | ☐ All Pass ☐ Fail (do not count in KPI) |

**Publishing gate failures to watch (from demo review):**
- Unsafe advice without follow-up route (e.g. “no need to worry about hitting head” with no escalation)
- Guideline violations (e.g. mother tasting food before child without proper temp-check guidance)

---

## 7. KPI rules checklist

| # | Rule | ☐ Acknowledged |
|---|------|----------------|
| 1 | Denominator = **pipeline execution time only** (no dev/debug/meetings) | |
| 2 | Denominator **includes medical review** for all 3 languages | |
| 3 | Tracking starts after **≥1 full E2E pipeline** completion | |
| 4 | **Weekly Monday snapshots** during project | |
| 5 | **Peak weekly snapshot** = final achievement KPI | |
| — | KPI formula changes require **CEO agreement** only | |

---

---

# PART B — 한국어

---

## 1. 시간 구분 (기록 전 필독)

| 구분 | 예시 | KPI 분모 포함? |
|------|------|----------------|
| **인턴십 시간** (13주 고정 자원) | 시스템 개발, 파이프라인 설계, 학습, 디버깅, 미팅, 리서치, 브레인스토밍, 실패한 실험 | **아니오** |
| **파이프라인 실행 시간** (KPI 분모) | 소스 선정 → 퍼블리시까지 한 편 처리 시 사람이 반복 개입한 시간 (EN/KO/ES 의학 리뷰 포함) | **예** |

> 측정 대상은 **파이프라인 자동화 수준**이지, 시스템 구축에 쓴 총 시간이 아닙니다.

---

## 2. 편당 파이프라인 시간 기록표

*퍼블리시된 영상 1편당 1행. 의학 리뷰 **Pass**만 집계.*

**영상 ID / 제목:** ________________________________  
**퍼블리시일:** __________ **파이프라인 포맷:** ☐ A (Q&A) ☐ B (뉴스레터) ☐ C (밈/트렌드) ☐ 기타: ______  
**배포 언어:** ☐ EN ☐ KO ☐ ES  
**배포 채널:** ☐ YouTube ☐ MoDoc 블로그 ☐ Instagram ☐ Facebook  

| 구간 | 담당 | 분 | 비고 |
|------|------|-----|------|
| 1. 콘텐츠 선정 및 추출 | 인턴 팀 | | |
| 2. 포맷 결정 / 라우팅 | 인턴 / AI router | | |
| 3. 비디오 제작 | 인턴 / 파이프라인 | | Baseline(제작만): 중앙값 **45분**, 평균 **53분** |
| 4. 의학적 리뷰 (3개국어) | MC + Dr.Sam | | 참고: EN·KO 각 ~1분/편, ES ~10분/편 (5편 샘플) |
| 5. 업로드 및 퍼블리시 (전 채널) | PM | | YouTube + 블로그 임베드 + IG + FB |
| **파이프라인 실행 시간 합계** | | **____ 분** | **이 영상의 KPI 분모** |

**기록자:** ________________ **날짜:** __________

---

## 3. 주간 조회수 기록표

*해당 기간 퍼블리시 영상의 전 채널 조회수 합산.*

| 영상 ID | 퍼블리시일 | YouTube | MoDoc 블로그 | Instagram | Facebook | **행 합계** |
|---------|-----------|---------|-------------|-----------|----------|------------|
| | | | | | | |
| | | | | | | |
| | | | | | | |
| **주간 Σ 조회수** | | | | | | **________** |

---

## 4. 주간 KPI 스냅샷 (매주 월요일)

**주차 #:** ____ **스냅샷 일자 (월):** __________  
**E2E 파이프라인 가동?** ☐ 예 (KPI 집계 시작) ☐ 아니오 (규칙 3 — 아직 집계 안 함)

| 지표 | 이번 주 | 누적 (프로젝트 시작~현재) |
|------|---------|-------------------------|
| Σ 조회수 (전 플랫폼) | | |
| Σ 파이프라인 실행 시간 (분) | | |
| **주간 KPI** = Σ 조회수 ÷ Σ 시간 (시간) | **________ 조회/시간** | **________ 조회/시간** |
| 퍼블리시 편수 (리뷰 Pass) | | |
| 참여 인턴 수 | | |

**현재까지 피크 KPI (규칙 5):** __________ 조회/시간 · **달성 주차:** ______

**메모 (자동화 성과, 병목, 실험):**

```
```

**작성:** ________________ **검토 (CEO/PM):** ________________

---

## 5. KPI 등급 평가

*프로젝트 기간 **누적 피크 KPI**를 baseline·킥오프 target 대비 평가. CEO가 킥오프 시 등급 기준 조정 가능.*

| 등급 | 라벨 | 기준 (파이프라인 실행 1시간당 조회수) |
|------|------|-------------------------------------|
| ☐ **5 — 탁월** | 피크 KPI ≥ 킥오프 target의 **150%** | |
| ☐ **4 — 우수** | 피크 KPI ≥ 킥오프 target의 **100%** | |
| ☐ **3 — 순항** | 피크 KPI ≥ baseline composite의 **100%** | |
| ☐ **2 — baseline 미달** | 피크 KPI ≥ baseline composite의 **50%** | |
| ☐ **1 — 개입 필요** | 피크 KPI < baseline composite의 **50%** | |

**Baseline composite (킥오프 시 확정):**

```
편당 파이프라인 실행 시간 = 선정·추출 + 포맷 결정 + 제작 + 의학 리뷰 + 업로드·퍼블리시
Baseline 제작만 (측정 완료): 중앙값 45분 · 평균 53분 · 범위 25–100분
편당 전체 baseline: __________ 분 (TBD)
Baseline KPI (조회/시간): __________ (TBD — CEO와 조회 집계 기간 합의 후)
킥오프 target KPI: __________ 조회/시간
```

**최종 달성 KPI (프로젝트 종료 시):** __________ 조회/시간 · **등급:** ☐ 1 ☐ 2 ☐ 3 ☐ 4 ☐ 5

---

## 6. 산출량 및 품질 게이트 (참고 — 메인 KPI 아님)

| 항목 | 목표 | 이번 주 |
|------|------|---------|
| 퍼블리시 산출 | **인턴 1인당 주 3편** (Pass만) | |
| 팀 용량 예시 | 6명 × 3소스 × 3언어 = **54편** (baseline 참고) | |
| 의학적 리뷰 | 퍼블리시 전 **Pass 필수** | ☐ 전부 Pass ☐ Fail (KPI 제외) |

**퍼블리싱 게이트 주의 (데모 리뷰 기준):**
- 추가 정보·에스컬레이션 없이 “걱정 말라”류 안전하지 않은 조언
- 가이드라인 위반 (예: 온도 확인 없이 어머니가 먼저 맛보는 장면)

---

## 7. KPI 규칙 체크리스트

| # | 규칙 | ☐ 확인 |
|---|------|--------|
| 1 | 분모 = **파이프라인 실행 시간만** (개발·디버깅·회의 제외) | |
| 2 | 분모에 **3개국어 의학 리뷰** 포함 | |
| 3 | **E2E 파이프라인 1회 이상** 완성 후 집계 시작 | |
| 4 | 프로젝트 기간 **매주 월요일** 스냅샷 | |
| 5 | **주간 스냅샷 최댓값** = 최종 달성 KPI | |
| — | KPI 변경은 **CEO 협의**로만 가능 | |

---

## 8. KPI 계산 예시 | Calculation example

**English:**  
3 videos published this week · Total views = 12,000 · Total pipeline time = 180 min (3 hr)  
→ Weekly KPI = 12,000 ÷ 3 = **4,000 views/hr**

**한국어:**  
이번 주 3편 퍼블리시 · 총 조회수 12,000 · 총 파이프라인 실행 시간 180분 (3시간)  
→ 주간 KPI = 12,000 ÷ 3 = **4,000 조회/시간**

---

*Modoc AI · Internship KPI Form · Changes require CEO sign-off*
