# devops-day-lab 결정 기록

이 문서는 "왜 이렇게 정했는가"만 담는다. 무엇을 어떻게 만드는지는 [README.ko.md](README.ko.md)와 [docs/guide.ko.md](docs/guide.ko.md).

## 제약과 결정 (2026-10-31)

- **버스와 Lambda 사이에 SQS를 둔다.** 복구 런북의 핵심인 `sqs:StartMessageMoveTask`는 SQS 큐의 데드레터 큐로 설정된 큐에서만 재처리할 수 있다. Lambda나 EventBridge가 직접 쓰는 데드레터 큐는 지원하지 않는다(SQS API 레퍼런스에 명시). 그래서 EventBridge 규칙이 Lambda가 아니라 `devops-day-lab-orders` 큐로 보내고, 그 큐의 RedrivePolicy가 데드레터 큐를 가리킨다. 콘솔의 「Start DLQ redrive」 버튼과 같은 경로다.
- **FIS 중단 조건은 호출용 알람이 아니라 별도의 blast-radius 알람이다.** 오류 실험은 1분에 오류 5건으로 `consumer-errors` 알람을 2분쯤에 울린다. 그 알람을 중단 조건으로 걸면 첫 주문이 데드레터 큐에 도착하기도 전에 실험이 스스로 멈춰 4단계(런북 재처리)가 성립하지 않는다. 그래서 중단 조건은 데드레터 100건 초과(`devops-day-lab-blast-radius`)로 따로 두었다. 호출하는 알람과 멈추는 알람이 다르다는 점 자체가 가르칠 내용이다.
- **Incident Manager는 쓰지 않는다.** 온콜 교대·에스컬레이션·대응 계획의 정답이지만 2025-11-07부터 신규 고객을 받지 않는다(문서: "no longer open to new customers"). 이 계정은 그 전에 활성화한 적이 없어 쓸 수 없다. AWS가 안내하는 대안은 OpsCenter와 파트너(PagerDuty 등)다. 대체 구성: 알림은 SNS(이메일·SMS)와 User Notifications(Console Mobile App 푸시), 티켓은 OpsCenter OpsItem(알람 액션 ARN `arn:aws:ssm:…:opsitem:<심각도>#CATEGORY=<카테고리>`), 복구는 Systems Manager Automation 런북. 교대는 구현하지 않고 가이드에서 개념으로만 다룬다.
- **Powertools를 쓰지 않는다.** 구조화 로그는 `json.dumps` 한 줄, 앱 지표는 임베디드 메트릭 포맷(EMF) 한 줄로 충분하다. 의존성이 0이라 `sam build`가 없고, CloudShell에서 `git clone` 뒤 `./scripts/setup.sh` 한 번으로 끝나는 event-scraper와 같은 흐름을 유지한다. Logs Insights 쿼리와 대시보드 지표가 되는지가 목적이고 라이브러리가 목적이 아니다.
- **producer Lambda를 두지 않는다.** 부하는 EventBridge Scheduler의 universal target(`arn:aws:scheduler:::aws-sdk:eventbridge:putEvents`)이 1분마다 주문 10개를 버스에 직접 올린다. 수동 호출은 `scripts/send.sh`가 `aws events put-events`로 한다. 함수가 하나라 배우는 사람이 볼 곳도 하나다.
- **새 버전 발행은 `Release` 파라미터로 강제한다.** 카나리 롤백 실습의 「나쁜 배포」는 코드가 아니라 `Bug=on` 환경변수 변경이다. SAM은 코드 해시가 바뀔 때만 새 버전을 발행하고, `AutoPublishAliasAllProperties: true`도 `Ref`가 들어간 환경변수는 해시에 반영하지 못한다(로컬 SAM 변환으로 확인: `Bug` 값이 바뀌어도 Version 논리 ID가 같았다). 그래서 `AutoPublishCodeSha256: !Ref Release`로 두고 `setup.sh`와 `release.sh`가 `Release=<Bug 값><src/consumer.py 체크섬>`을 넘긴다. 설정 변경도 코드 변경도 새 버전이 된다. 카나리는 `Canary10Percent10Minutes`다. 5분이면 분당 주문 10개 중 10%만 새 버전에 가서 한 번도 안 닿을 확률이 몇 퍼센트 남는다.
- **카나리 알람은 ExecutedVersion 차원으로 센다.** `canary-errors`는 `FunctionName` + `Resource`(`live` 별칭) + `ExecutedVersion`(새 버전) 차원의 Errors를 세고 임계값은 1건이다. 전체 오류를 세면 10% 트래픽에서 1분 안에 임계값에 닿지 않는다. 온콜용 `consumer-errors`(임계값 5건)와 분리해 카나리가 고객보다 먼저 알게 한다.
- **버킷에 버저닝·Retain을 두지 않는다.** 실습 데이터만 들어가고 `scripts/teardown.sh`가 비우고 지운다. 운영 기준(버저닝, DeletionPolicy Retain)은 여기서는 삭제를 방해하기만 한다. 퍼블릭 액세스 차단, 기본 암호화, HTTPS 전용 정책은 유지한다. 한 버킷에 `archive/`(처리된 주문)와 `fis/`(FIS 장애 설정 전달 지점) 두 접두사를 쓴다.
- **BatchSize 1.** 메시지 하나가 호출 하나다. 재시도·데드레터가 주문 단위로 떨어지고, 부분 배치 실패 처리 코드가 필요 없다. 처리량이 목적이 아니다.
- **카오스는 앱 안의 플래그가 아니라 AWS FIS로 한다.** SSM 파라미터로 consumer가 스스로 실패하게 만드는 쪽이 서비스도 권한도 적지만, 실험 템플릿·중단 조건·확장 레이어·S3 설정 전달이라는 실제 도구의 모양을 보는 것이 실습의 목적이다. 비용은 액션 1분에 $0.10, 실험 하나(4분)에 $0.40. Lambda 확장 레이어 ARN은 리전마다 달라 공개 SSM 파라미터 `/aws/service/fis/lambda-extension/AWS-FIS-extension-x86_64/1.x.x`를 템플릿 파라미터로 받는다.
- **SMS는 SNS SMS 샌드박스 안에서 한다.** 모든 계정은 샌드박스에서 시작하고 인증한 번호에만 문자를 보낸다. 인증 코드는 15분 유효, 번호당 24시간에 5회까지 요청할 수 있다. `scripts/setup.sh`가 등록과 인증을 처리하고 번호는 `Phone` 파라미터로 템플릿의 SMS 구독에 들어간다. 샌드박스 탈출(프로덕션 액세스 신청)은 하지 않는다.
- **리소스 이름은 `devops-day-lab`로 통일.** 스택·버스·큐·함수·알람·런북이 모두 이 접두사를 쓴다. `iam/lab-policy.json`의 IAM 권한도 `devops-day-lab-*` 역할로 제한한다.

## 하지 말 것

현 단계에서 범위 밖. 제안하지도, 추가하지도 말 것.

- Incident Manager - 신규 고객 불가
- 온콜 교대 자동화(Scheduler + Lambda), PagerDuty 연동 - 개념 설명으로 충분
- Powertools, 외부 패키지, `sam build`
- API Gateway, Function URL - 부하는 Scheduler, 수동 호출은 CLI
- DynamoDB, Step Functions, VPC
- FIS 실험 로그 설정, FIS 리포트($5/건)
- 멀티 리전, 멀티 계정 실험
