# 발표 원고: DevOps 체험하기: 카오스 엔지니어링(AWS FIS)과 온콜 대응(CloudWatch, SNS, OpsCenter)

이 문서는 발표 슬라이드를 만들 때 그대로 옮겨 쓰는 원고입니다. 슬라이드마다 제목, 핵심 메시지 한 문장, 본문 불릿, 발표자 노트, 화면 제안을 적었습니다. 수치는 모두 이 저장소의 `template.yaml`과 `scripts/`에 있는 값이거나 AWS 공식 문서에서 확인한 값입니다. 실제 실행 결과 수치(걸린 시간, 알람이 울린 시각)는 실습 당일 직접 적어 넣습니다.

---

## 1. 제목

**DevOps 체험하기: 카오스 엔지니어링(AWS FIS)과 온콜 대응(CloudWatch, SNS, OpsCenter)**

부제: Lambda 하나를 부수고 고치는 55분

- 핵심 메시지: 오늘은 코드를 짜는 날이 아니라, 돌아가는 서비스를 운영하는 날입니다.
- 불릿
  - 주문 파이프라인 하나를 배포합니다.
  - 일부러 장애를 냅니다.
  - 알람을 받고, 티켓을 열고, 런북으로 복구합니다.
  - 잘못된 배포가 스스로 되돌아가는 것을 봅니다.
- 발표자 노트: 참가자가 가져가는 것은 서비스가 아니라 경험입니다. 55분 뒤에는 "장애가 나면 무엇이 울리고, 어디를 보고, 무엇을 누르는가"를 한 번 손으로 해본 상태가 됩니다. 저장소 주소와 CloudShell 접속 방법을 이 슬라이드에 함께 적어 둡니다.
- 화면: 저장소 README 상단과 `docs/architecture.png`.

## 2. 왜 DevOps 실습인가

**배포는 하루면 배우지만, 운영은 사고가 나야 배웁니다. 그래서 사고를 만듭니다.**

- 불릿
  - 서버리스라도 장애는 납니다. 재시도, 적체, 느려짐, 잘못된 배포.
  - 장애 대응은 세 가지 질문입니다. 언제 알았나, 무엇을 봤나, 어떻게 되돌렸나.
  - 이 질문을 안전한 계정에서 미리 한 번 답해 봅니다.
  - 전 과정이 CloudShell 스크립트 6개로 끝납니다. 설치할 것이 없습니다.
- 발표자 노트: 실무에서 처음 받는 온콜 알람은 대부분 새벽이고, 그때 처음 보는 콘솔 화면은 기억에 남지 않습니다. 오늘은 낮에, 커피 들고, 같은 화면을 봅니다. "카오스 엔지니어링"이라는 말이 거창하게 들리지만 내용은 "통제된 조건에서 고장을 재현하고 관측한다"는 것뿐입니다.
- 화면: `scripts/` 폴더 목록(setup, send, chaos, release, redrive, teardown).

## 3. 오늘의 앱

**주문이 들어오면 큐에 쌓이고, Lambda가 처리해 S3에 보관하는 파이프라인입니다.**

- 불릿
  - EventBridge 버스 `devops-day-lab-bus`, 규칙은 `source=lab.shop`, `detail-type=OrderPlaced`.
  - SQS `devops-day-lab-orders`가 받습니다. 가시성 제한 30초, 3번 실패하면 DLQ로 보냅니다.
  - Lambda `devops-day-lab-consumer`(Python 3.12, 256 MB, 제한 시간 5초)가 한 건씩 꺼내 S3 `archive/`에 JSON으로 저장합니다.
  - EventBridge Scheduler가 1분마다 주문 10건을 넣습니다. 그래프와 알람에 항상 데이터가 있습니다.
- 발표자 노트: 주문 10건은 커피, 베이글, 라떼처럼 품목과 금액이 다릅니다. 나중에 Logs Insights에서 품목별 합계를 뽑아 보는 데 씁니다. `scripts/send.sh`는 같은 이벤트를 손으로 넣는 "가상 API"입니다. 참가자가 "내가 넣은 주문이 지나갔다"를 눈으로 확인하는 용도입니다.
- 화면: `docs/architecture.png`에서 왼쪽 가로줄(CloudShell, Scheduler, EventBridge, SQS, Lambda, S3)만 보이게 확대.

## 4. 서비스 지도

**서비스 12개가 역할 5개로 나뉩니다. 이름보다 역할을 기억합니다.**

- 불릿
  - 앱: EventBridge, EventBridge Scheduler, SQS, Lambda, S3
  - 배포: CodeDeploy(SAM `DeploymentPreference`가 자동 생성)
  - 관측: CloudWatch(지표, 로그, 알람, 대시보드), X-Ray
  - 카오스: AWS FIS
  - 온콜과 복구: SNS, Systems Manager OpsCenter, Systems Manager Automation
- 발표자 노트: 표로 보여 주면 "서비스가 많다"는 인상이 먼저 옵니다. 그래서 역할 다섯 줄로 묶습니다. 전부 `template.yaml` 한 파일, `sam deploy` 한 번입니다. IAM 역할 세 개(Lambda 실행, Scheduler, FIS)도 그 안에 있습니다.
- 화면: `docs/architecture.png` 전체. 그 옆에 역할 5줄 표.

| 역할 | 서비스 | 템플릿에서 하는 일 |
|---|---|---|
| 앱 | EventBridge, Scheduler, SQS, Lambda, S3 | 주문 생성, 전달, 처리, 보관 |
| 배포 | CodeDeploy | `Canary10Percent10Minutes`, 알람 시 자동 롤백 |
| 관측 | CloudWatch, X-Ray | 알람 5개, 대시보드 1개, 추적 활성화 |
| 카오스 | AWS FIS | 실험 템플릿 2개, 중단 조건 1개 |
| 온콜·복구 | SNS, OpsCenter, Automation | 메일·SMS, OpsItem 자동 생성, DLQ 재처리 런북 |

## 5. 정상이 무엇인가

**정상 상태를 먼저 외워야 장애가 보입니다. 숫자 네 개를 적어 둡니다.**

- 불릿
  - 대시보드 `devops-day-lab`: 분당 호출 10, 오류 0, p95 지연, 큐 깊이 0.
  - 구조화 로그: Lambda가 주문마다 JSON 한 줄(`order_id`, `item`, `amount`, `ms`)을 남깁니다.
  - Logs Insights: `stats sum(amount) by item`으로 품목별 매출을 바로 뽑습니다.
  - X-Ray 서비스 맵: Lambda 서비스 노드와 함수 노드, 호출별 소요 시간 분포.
- 발표자 노트: 여기서 참가자에게 종이에 네 숫자(호출, 오류, p95, DLQ)를 적게 합니다. 장애 단계에서 이 숫자가 어떻게 변하는지 비교하는 것이 실습의 뼈대입니다. 앱 지표 `DevOpsDayLab/OrdersArchived`는 SDK 호출 없이 로그 한 줄(embedded metric format)로 만든 지표라는 점도 짚어 줍니다.
- 화면: CloudWatch 대시보드 `devops-day-lab` 전체 화면. 알람 위젯 5개가 모두 OK인 상태.

## 6. 카오스 엔지니어링

**통제된 고장입니다. 얼마나, 어디까지, 언제 멈출지를 먼저 정합니다.**

- 불릿
  - AWS FIS Lambda 액션 2개: `aws:lambda:invocation-error`(호출을 실패로 처리), `aws:lambda:invocation-add-delay`(시작 전 지연).
  - 실험 템플릿 2개: 오류 4분(100%, 함수 코드 실행 없이 바로 실패), 지연 4분(100%, 3,000 ms).
  - 동작 원리: FIS Lambda 확장 레이어가 함수에 붙고, FIS가 S3 `fis/` 접두사에 고장 설정을 써 두면 확장이 읽어 적용합니다.
  - 중단 조건: DLQ 100건 초과 알람 `devops-day-lab-blast-radius`. 이 알람이 울리면 실험이 스스로 멈춥니다.
- 발표자 노트: 중단 조건을 온콜용 알람과 분리한 이유를 설명합니다. 실험은 온콜을 깨워야 하지만, 피해가 바보 같은 수준이 되기 전에 스스로 멈추기도 해야 합니다. 그래서 "1건이면 호출"과 "100건이면 중단"을 다른 알람으로 둡니다. 레이어 ARN은 SSM 공개 파라미터 `/aws/service/fis/lambda-extension/AWS-FIS-extension-x86_64/1.x.x`로 받아 리전마다 손으로 바꿀 일이 없습니다.
- 화면: FIS 콘솔의 실험 템플릿 상세(액션, 대상, 중단 조건 탭)와 `scripts/chaos.sh start error` 출력.

## 7. 장애가 보이는 순간

**알람 3개가 서로 다른 질문에 답합니다. 실패하나, 쌓였나, 느린가.**

- 불릿
  - `devops-day-lab-consumer-errors`: 1분에 오류 5건 이상. 심각도 2 OpsItem과 메일·SMS.
  - `devops-day-lab-dlq-not-empty`: DLQ에 1건 이상. 심각도 3 OpsItem과 메일·SMS.
  - `devops-day-lab-consumer-slow`: p95 지연 2,000 ms 초과. 심각도 4 OpsItem과 메일·SMS.
  - 오류 실험을 켜면 메시지가 30초마다 재시도되어 3번째 실패 후 DLQ로 갑니다. 템플릿 값으로 계산하면 실험 시작 2~3분 안에 첫 알림이 옵니다.
- 발표자 노트: 알림 경로는 CloudWatch 알람에서 SNS 토픽 `devops-day-lab-oncall`로, 거기서 이메일과 SMS로 갑니다. 휴대폰 푸시는 AWS User Notifications에서 Console Mobile App을 전달 채널로 붙여 받습니다(콘솔에서 한 번 설정, 가이드 참조). SMS는 계정이 SNS SMS 샌드박스에 있어 인증한 번호에만 가고, `setup.sh`가 인증 코드 입력까지 안내합니다. 실제 걸린 시간은 당일 실측값을 이 슬라이드에 적습니다.
- 화면: 휴대폰 알림 캡처(메일 또는 SMS)와 대시보드의 알람 위젯이 빨갛게 바뀐 장면을 나란히.

## 8. 온콜

**온콜은 "알람이 울리면 누가 받는가"입니다. 오늘은 SNS 구독자가 당번입니다.**

- 불릿
  - 당번 = SNS 토픽을 구독한 사람. 교대와 에스컬레이션은 이번 실습에서 구현하지 않습니다.
  - AWS에서 그 역할을 하던 Systems Manager Incident Manager는 2025년 11월 7일부터 신규 고객을 받지 않습니다. 이미 활성화된 계정만 계속 쓸 수 있습니다.
  - AWS가 안내하는 대안: 운영 이슈 관리는 Systems Manager OpsCenter, 자동 호출과 교대는 파트너 솔루션(Jira Service Management, ServiceNow, PagerDuty 마이그레이션 가이드 제공).
  - 그래서 이 실습은 OpsCenter를 티켓으로, SNS를 호출기로 씁니다.
- 발표자 노트: 참가자 중 누군가는 "AWS에 PagerDuty 같은 서비스 없나요"라고 묻습니다. 있었고, 지금은 새 계정에서 못 켭니다. 이 사실 자체가 운영의 교훈입니다. 서비스는 사라지기도 하고, 아키텍처는 그걸 견뎌야 합니다. 교대를 꼭 체험하고 싶다면 EventBridge Scheduler가 당번 파라미터를 바꾸는 방식으로 흉내 낼 수 있다는 것만 언급합니다.
- 화면: Incident Manager 공식 문서의 안내문(새 고객 수용 중단)과 OpsCenter 콘솔 첫 화면.

## 9. OpsItem과 런북

**티켓은 자동으로 열리고, 복구는 버튼 하나로 끝납니다. 사람은 원인을 확인하는 데 시간을 씁니다.**

- 불릿
  - 알람이 ALARM 상태가 되면 OpsCenter에 OpsItem이 생깁니다. 심각도, 알람 이력, 관련 리소스가 한 화면에 옵니다.
  - 원인 확인: Logs Insights에서 오류 로그를 보고, FIS 콘솔에서 실행 중인 실험을 봅니다. `scripts/chaos.sh stop`으로 원인을 제거합니다.
  - 복구: Automation 문서 `devops-day-lab-redrive-dlq`를 실행합니다. 내용은 `sqs:StartMessageMoveTask` 한 단계, 초당 10건으로 DLQ의 주문을 원래 큐로 되돌립니다.
  - 되돌아간 주문이 처리되면 DLQ 알람이 OK로 바뀌고 OK 알림 메일이 옵니다. OpsItem에 원인과 조치를 적고 해결 처리합니다.
- 발표자 노트: 순서가 중요합니다. 원인을 없애기 전에 재처리하면 주문이 다시 실패해 DLQ로 돌아옵니다. 런북 설명문에도 그렇게 적어 두었습니다. `scripts/redrive.sh`는 같은 문서를 터미널에서 실행하고 DLQ 잔량을 출력합니다. 콘솔에서 하든 스크립트로 하든 실행 이력은 Automation에 남습니다.
- 화면: OpsItem 상세 화면(타임라인 탭)과 Automation 실행 결과 화면.

## 10. MTTD와 MTTR

**숫자 두 개로 오늘 대응을 평가합니다. 다음 실습의 목표도 이 숫자입니다.**

- 불릿
  - 장애 시작 시각: `scripts/chaos.sh start`가 출력한 시각.
  - 탐지 시각: 첫 알림(메일, SMS, 푸시)이 도착한 시각. MTTD = 탐지 - 시작.
  - 복구 시각: DLQ 알람이 OK로 돌아온 시각. MTTR = 복구 - 시작.
  - 다음 질문: 탐지를 1분 줄이려면 어떤 알람 값을 바꿔야 하는가. 복구를 줄이려면 어떤 단계를 자동화해야 하는가.
- 발표자 노트: 참가자들이 적어 둔 시각으로 각자 계산합니다. 조별로 숫자를 비교하면 알람 주기(60초)와 재시도 간격(30초)이 어디에 들어가 있는지 자연스럽게 드러납니다. "탐지가 늦었다"가 아니라 "탐지가 늦도록 설계된 값이 어디에 있나"로 질문을 바꿉니다.
- 화면: 빈 표 한 장(시작, 탐지, 복구, MTTD, MTTR). 발표 중 직접 채웁니다.

## 11. 안전한 배포

**배포도 장애의 원인입니다. 그래서 10%만 먼저 보내고, 알람 한 건이면 되돌립니다.**

- 불릿
  - `scripts/release.sh on`은 `Bug=on`으로 스택을 다시 배포합니다. 새 버전은 주문마다 예외를 던집니다.
  - SAM `DeploymentPreference: Canary10Percent10Minutes`. CodeDeploy가 트래픽 10%를 새 버전으로 10분간 보냅니다.
  - 알람 `devops-day-lab-canary-errors`는 새 버전(`ExecutedVersion`)의 오류만 셉니다. 1건이면 울립니다.
  - CodeDeploy가 롤백하고 CloudFormation은 업데이트 실패로 끝납니다. 온콜용 알람(1분 5건)은 울리지 않습니다. 고객이 모르는 사이에 끝난 장애입니다.
- 발표자 노트: 핵심은 알람의 차원입니다. 함수 전체 오류를 보는 알람으로는 카나리 10%의 실패가 임계값에 닿지 않습니다. 새 버전만 보는 알람이 따로 있어야 롤백이 됩니다. SAM은 코드가 바뀔 때만 새 버전을 발행하므로, 스크립트가 `Release` 파라미터(`Bug` 값 + 코드 체크섬)를 바꿔 환경 변수만 바뀌어도 새 버전이 발행되게 했습니다. 실패한 메시지는 재시도 때 90% 확률로 옛 버전에 가서 성공하므로 DLQ에 쌓이지 않습니다.
- 화면: CodeDeploy 배포 상세 화면(트래픽 이동 그래프와 롤백 이벤트), 그 뒤 CloudFormation 스택 상태 `UPDATE_ROLLBACK_COMPLETE`.

## 12. 비용과 정리

**실습 1회 약 1달러입니다. 끝나면 스크립트 하나로 지웁니다.**

- 불릿
  - AWS FIS: 액션 1분당 0.10달러. 실험 2개 × 4분 = 0.80달러.
  - OpsCenter: OpsItem 1,000건당 2.97달러. 오늘은 몇 건입니다.
  - Lambda, SQS, SNS 이메일, CloudWatch, X-Ray, CodeDeploy는 이 실습 규모에서는 거의 비용이 없습니다. SMS는 통신사 요율로 건당 과금됩니다.
  - `scripts/teardown.sh`: 실행 중인 실험 중지, S3 버킷 비우기, `sam delete`. OpsItem과 인증한 SMS 번호는 남습니다.
- 발표자 노트: 비용 슬라이드는 짧게 갑니다. FIS는 분 단위 과금이라 실험 시간을 4분으로 잡은 것, 그리고 중단 조건이 비용 상한이기도 하다는 점을 연결합니다. 정리는 반드시 수업 안에서 끝냅니다. Scheduler가 1분마다 이벤트를 넣으므로 켜 둔 채 잊으면 로그가 계속 쌓입니다.
- 화면: `scripts/teardown.sh` 출력과 CloudFormation 스택 목록이 비어 있는 화면.

## 13. 회고 질문

**오늘 본 것을 각자의 서비스에 옮기는 질문 세 개입니다.**

- 불릿
  - 내 서비스에서 "정상"을 설명하는 숫자 네 개는 무엇인가.
  - 지금 울리는 알람 중 사람이 새벽에 일어나야 하는 것은 몇 개인가. 나머지는 왜 알람인가.
  - 내 배포는 실패했을 때 누가 되돌리는가. 사람인가, 알람인가.
- 발표자 노트: 답을 받지 않습니다. 각자 적게 하고 다음 주에 다시 묻습니다. 셋 다 오늘 실습의 단계(기준선, 알람, 카나리)에 대응합니다.
- 화면: 질문 세 줄만. 다른 요소 없음.

## 14. 다음 단계

**오늘 뺀 것들입니다. 각각 반나절 실습으로 이어집니다.**

- 불릿
  - 교대와 에스컬레이션: CloudWatch에서 SNS를 거쳐 PagerDuty로 보내고 스케줄을 PagerDuty에서 관리합니다.
  - 이벤트 기반 아키텍처 확장: 버스에 소비자를 더 붙이고, 아카이브 보관과 재생(replay)을 다룹니다.
  - SLO: CloudWatch Application Signals로 "주문 처리 성공률 99.9%" 같은 목표를 정의하고 오차 예산을 봅니다.
  - 지연 실험: 오늘 안 돌렸다면 `scripts/chaos.sh start delay`로 "느린 장애"를 겪어 봅니다. 오류 없이 p95만 오르는 경우입니다.
- 발표자 노트: 지연 실험은 55분 안에 들어가지 않아 다음 단계로 뺐습니다. 3,000 ms 지연은 제한 시간 5초 안이라 실패는 없고 `consumer-slow` 알람만 울립니다. "오류는 없는데 고객이 불만을 말하는" 상황의 축소판입니다.
- 화면: 저장소 README의 "다음 단계" 절, 혹은 이 네 줄만.

---

## 발표 운영 메모

### 55분 진행표

| 시간 | 단계 | 띄우는 슬라이드 | 참가자가 하는 일 |
|---|---|---|---|
| 0:00~0:05 | 시작 | 1, 2 | 저장소 주소 확인, CloudShell 열기 |
| 0:05~0:15 | 배포 | 3, 4 | `git clone`, `./scripts/setup.sh`(이메일, 선택 SMS), 구독 확인 메일 클릭 |
| 0:15~0:25 | 기준선 | 5 | 대시보드 열기, 숫자 네 개 적기, Logs Insights 쿼리, X-Ray 맵 |
| 0:25~0:35 | 부수기 | 6, 7, 8 | `./scripts/chaos.sh start error`, 시각 적기, 알림 받기, OpsItem 확인 |
| 0:35~0:45 | 대응 | 9, 10 | 원인 확인, `./scripts/chaos.sh stop`, 런북 실행, OpsItem 해결, MTTD·MTTR 계산 |
| 0:45~0:52 | 배포 롤백 | 11 | `./scripts/release.sh on`, CodeDeploy 화면 관찰 |
| 0:52~0:55 | 정리 | 12, 13, 14 | `./scripts/teardown.sh`, 회고 질문 적기 |

- 슬라이드 6~8은 실험을 켠 뒤 알림이 올 때까지 기다리는 2~3분 동안 설명합니다. 기다리는 시간이 발표 시간입니다.
- 슬라이드 11은 `release.sh on` 실행 직후 띄웁니다. 롤백까지 보통 2분 안이고, 그 사이에 알람 차원(`ExecutedVersion`) 이야기를 합니다.
- 배포 단계에서 `sam deploy`가 끝나기를 기다리는 동안 슬라이드 3, 4를 설명합니다. 첫 배포는 CodeDeploy 리소스 생성 때문에 몇 분 걸립니다.

### 30분 단축 경로

- 진행: 배포(10분) → 부수기(8분) → 대응(8분) → 정리(4분).
- 띄우는 슬라이드: 1, 3, 6, 7, 9, 12. 기준선은 배포 대기 중에 대시보드를 한 번 보여 주는 것으로 대신합니다.
- 빼는 슬라이드: 2, 4, 5, 8, 10, 11, 13, 14. 특히 11(카나리 롤백)은 배포 왕복에 5분 이상 들어 30분 안에 넣지 않습니다.
- 참가자가 적는 시각은 두 개만: 실험 시작, 첫 알림 도착. MTTD만 계산합니다.

### 발표 전 확인

- 발표자 계정에 스택을 미리 올려 두고 대시보드와 OpsCenter 화면을 캡처해 둡니다. 당일 네트워크가 느려도 화면은 있습니다.
- 캡처에서 계정 ID, 이메일, 전화번호는 가립니다.
- 참가자 계정에 `iam/lab-policy.json` 권한이 들어가 있는지 확인합니다. FIS, CodeDeploy, SQS, SNS, CloudWatch 권한이 없으면 `sam deploy`가 중간에 실패합니다.
- 이메일 구독 확인을 안 누른 참가자는 알림을 못 받습니다. 배포 단계 끝에 전원 확인합니다.
