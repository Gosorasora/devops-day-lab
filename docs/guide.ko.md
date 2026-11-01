# DevOps 체험하기: 카오스 엔지니어링(AWS FIS)과 온콜 대응(CloudWatch, SNS, OpsCenter)

실습 가이드 (55분, 30분 단축 경로 포함)

주문 파이프라인 하나를 배포하고, 정상 상태를 익히고, 일부러 부수고, 호출을 받아 대응하고, 망가진 버전을 카나리로 배포해 자동 롤백을 봅니다. 모든 명령은 저장소 루트의 AWS CloudShell에서 실행합니다.

**30분 단축 경로:** 1단계, 3단계, 4단계, 6단계만 합니다. 배포를 기다리는 동안 2단계를 1~2분만 봅니다. 5단계는 건너뜁니다. 단축 경로에 포함되는 단계는 제목에 `[30분]`이 붙어 있습니다.

## 사전 준비 (수업 전)

- AWS 계정. 배포에 쓰는 사용자나 역할에 `iam/lab-policy.json`을 붙여 둡니다. 샌드박스 계정에서 하세요.
- 콘솔에 로그인하고 리전을 서울(`ap-northeast-2`)로 둡니다. CloudShell은 상단 바의 `>_` 아이콘입니다.
- 알람을 받을 이메일 주소.
- 선택: SMS를 받을 휴대폰 번호(`+8210...` 형식). SMS는 건당 과금됩니다.
- 선택: AWS Console Mobile App을 설치하고 같은 계정으로 로그인해 둡니다(0단계).

## 0단계 (선택, 5분): Console Mobile App 푸시

AWS User Notifications가 CloudWatch 알람 상태 변화를 휴대폰 푸시로 보내 줍니다. 이 단계는 콘솔에서 수동으로 합니다. 필요한 AWS User Notifications 권한은 `iam/lab-policy.json`에 들어 있습니다.

1. 휴대폰의 Console Mobile App에서 알림을 켭니다. 기기가 User Notifications에 등록됩니다.
2. 콘솔에서 **User Notifications > Notification configurations > Create notification configuration**을 엽니다.
3. 이벤트 규칙: 소스 `aws.cloudwatch`, 이벤트 유형 **CloudWatch Alarm State Change**, 리전 `ap-northeast-2`.
4. 전달 채널: **AWS Console Mobile App**에서 등록한 기기를 고릅니다.

이제 3단계에서 알람이 울리면 메일과 함께 푸시가 옵니다.

## 1단계 [30분] (10분): 배포

```bash
git clone https://github.com/Gosorasora/devops-day-lab.git
cd devops-day-lab
./scripts/setup.sh
```

이메일을 묻습니다. 번호를 넣었다면 SNS가 보낸 일회용 코드를 묻습니다. `sam deploy`가 끝나면 대시보드 URL이 출력됩니다.

배포가 끝나기 전에 할 일 두 가지:

1. 「AWS Notification - Subscription Confirmation」 메일을 열어 **Confirm subscription**을 누릅니다. 승인 전에는 어떤 알람도 도착하지 않습니다.
2. 출력된 대시보드 URL을 새 탭에 열어 둡니다.

1분 안에 주문이 1분에 10개씩 흐르기 시작합니다. 스택 이름은 `devops-day-lab`, 함수 이름은 `devops-day-lab-consumer`입니다.

## 2단계 (10분): 기준선

정상을 모르면 장애도 모릅니다. 부수기 전에 정상이 어떻게 보이는지 세 곳에서 확인합니다.

**대시보드.** 위젯 여섯 개를 읽습니다.

- Alarms: 다섯 개 모두 OK.
- Orders: invocations vs errors: 1분에 10, 오류 0.
- Latency p50 / p95: 100 ms 안팎.
- Queue depth: orders vs dead-letter: 둘 다 0 근처.
- Orders archived: 앱이 직접 쓴 지표. 1분에 10.
- Last orders: 구조화 로그 표. `order_id`, `item`, `amount`, `ms` 열이 있습니다.

**Logs Insights.** CloudWatch > Logs Insights에서 로그 그룹 `/aws/lambda/devops-day-lab-consumer`를 고르고 실행합니다.

```
fields @timestamp, order_id, item, amount, ms | filter level = 'INFO' | stats sum(amount) by item
```

품목별 매출이 나옵니다. 로그가 JSON 한 줄이라서 쿼리가 됩니다.

**X-Ray 서비스 맵.** CloudWatch > X-Ray traces > Service map을 엽니다. Lambda 서비스 노드와 함수 노드가 보입니다(함수 안의 S3 호출은 X-Ray SDK가 없어 따로 그려지지 않습니다). 노드를 눌러 응답 시간 분포를 봅니다.

적어 둘 것: 정상 오류율(0), 정상 p95(밀리초), 정상 데드레터 깊이(0).

## 3단계 [30분] (10분): 부수기

```bash
scripts/chaos.sh start error
```

AWS FIS 실험 `devops-day-lab-error`가 시작됩니다. 4분 동안 모든 호출을 handler 실행 전에 실패시킵니다. 스크립트가 출력한 **시작 시각을 적어 둡니다.** 장애가 시작된 시각입니다.

이제 다음 순서로 일어납니다. 대시보드를 보면서 각 시각을 적습니다.

1. 1분 안에 Errors 그래프가 올라갑니다. FIS 확장이 10초마다 설정을 확인하므로 효과는 수십 초 뒤에 시작됩니다. 주문 하나가 30초 간격으로 세 번 실패합니다.
2. 1~2분 뒤 `devops-day-lab-consumer-errors` 알람이 ALARM이 됩니다(1분에 오류 5건 이상). 메일이 옵니다. 0단계를 했다면 푸시, 번호를 넣었다면 SMS도 옵니다.
3. 약 1분 뒤 첫 주문이 데드레터 큐에 도착하고 `devops-day-lab-dlq-not-empty` 알람이 ALARM이 됩니다.
4. Systems Manager > OpsCenter에 OpsItem이 생깁니다. 심각도 2(Availability)와 3(Recovery) 두 건입니다. 처음 OpsCenter를 열면 시작 화면이 나올 수 있습니다. 그대로 진행하면 됩니다.

FIS 콘솔에서 실험을 열어 **Stop conditions**를 봅니다. `devops-day-lab-blast-radius` 알람(데드레터 100건 초과)이 걸려 있습니다. 호출을 보내는 알람과 실험을 멈추는 알람은 다른 알람입니다. 실험이 스스로 피해 한계를 가집니다.

## 4단계 [30분] (10분): 대응

온콜이 받은 메일에는 알람 이름, 상태 변화 이유, 리전이 있습니다. 거기서 시작합니다.

1. **OpsItem을 엽니다.** Systems Manager > OpsCenter에서 `devops-day-lab-consumer-errors`로 만들어진 OpsItem을 엽니다. Related resources에 함수가, 알람 타임라인에 상태 변화가 있습니다.
2. **원인을 찾습니다.** Logs Insights에서 같은 로그 그룹에 다음을 실행합니다.

   ```
   fields @timestamp, @message | filter @message like /error|Error|FIS/ | sort @timestamp desc | limit 20
   ```

   FIS 확장이 남긴 메시지가 보입니다. 실제 장애라면 여기가 가장 오래 걸리는 구간입니다.
3. **원인을 제거합니다.** 4분이 지나 실험이 끝났을 수도 있습니다. 아직이면 멈춥니다.

   ```bash
   scripts/chaos.sh stop
   ```

4. **런북을 실행합니다.** 데드레터 큐의 주문을 원래 큐로 되돌립니다. OpsItem 화면의 **Runbooks**에서 `devops-day-lab-redrive-dlq`를 찾아 Execute로 실행하거나, 터미널에서 실행합니다.

   ```bash
   scripts/redrive.sh
   ```

   원인이 남아 있는 상태에서 되돌리면 주문은 다시 데드레터 큐로 갑니다. 그래서 3번이 먼저입니다.
5. **복구를 확인합니다.** 1분 안에 Queue depth의 dead-letter가 0으로 내려가고 알람 두 개가 OK로 돌아갑니다. OK 메일이 옵니다.
6. **OpsItem을 해결합니다.** 두 OpsItem에 원인, 조치, 재발 방지 한 줄씩을 적고 Resolved로 바꿉니다.

적어 둔 시각으로 두 숫자를 계산합니다.

- **MTTD** (탐지까지): 실험 시작 시각에서 첫 알람 메일까지.
- **MTTR** (복구까지): 실험 시작 시각에서 알람 OK까지.

## 5단계 (10분): 안전한 배포

장애의 흔한 원인은 배포입니다. 모든 주문에서 죽는 버전을 배포해 봅니다.

```bash
scripts/release.sh on
```

`Bug=on`으로 새 버전이 발행되고 CodeDeploy가 `Canary10Percent10Minutes`로 배포합니다. 트래픽의 10%만 새 버전으로 갑니다. 새 버전에 주문이 빨리 닿게 하려면 `scripts/send.sh 20`으로 주문을 더 넣어도 됩니다.

1. 출력된 CodeDeploy 콘솔 링크를 엽니다. 배포가 진행 중이고 트래픽 비율이 보입니다.
2. 1~2분 안에 `devops-day-lab-canary-errors` 알람이 ALARM이 됩니다. 이 알람은 새 버전(ExecutedVersion)의 오류만 셉니다. 오류 1건이면 울립니다.
3. CodeDeploy가 배포를 Failed로 바꾸고 트래픽을 이전 버전으로 되돌립니다. CloudFormation 스택은 `UPDATE_ROLLBACK_COMPLETE`가 됩니다. 터미널의 `sam deploy`는 실패 메시지를 출력합니다. 그것이 정상입니다.
4. 대시보드를 봅니다. 온콜 알람 `devops-day-lab-consumer-errors`는 보통 울리지 않습니다. 1분에 주문 10개 중 1개쯤만 새 버전에 갔고, 임계값은 5건입니다. 카나리가 고객보다 먼저 알았습니다.

## 6단계 [30분] (5분): 정리

```bash
./scripts/teardown.sh
```

실행 중인 실험을 멈추고, 버킷을 비우고, 스택을 삭제합니다. OpsCenter의 OpsItem은 남으니 해결 처리를 했는지 확인합니다. 부하 생성기는 스택과 함께 사라집니다. 삭제하지 않으면 1분에 10개씩 계속 돕니다.

## 더 해보기

- **느린 장애.** `scripts/chaos.sh start delay`는 4분 동안 모든 주문에 3초를 더합니다. 오류는 0인데 `devops-day-lab-consumer-slow` 알람(p95 2초 초과)이 울립니다. 오류율만 보면 놓치는 장애입니다.
- **가상 API.** `scripts/send.sh 5`는 주문 5개를 버스에 직접 올립니다. 상점이 API를 부르는 것과 같습니다. 대시보드와 S3 `archive/`에서 결과를 봅니다.

## 온콜이란

이 실습에서 온콜은 SNS 구독을 승인한 사람입니다. 알람은 토픽으로 가고, 토픽은 그 사람에게 갑니다.

실제 온콜에는 교대(rotation)와 에스컬레이션이 있습니다. 당번이 주마다 바뀌고, 응답이 없으면 다음 사람에게 넘어갑니다. AWS에서는 Incident Manager가 그 역할이었지만 2025년 11월 7일부터 신규 고객을 받지 않습니다(문서: "no longer open to new customers"). AWS가 안내하는 대안은 OpsCenter와 PagerDuty 같은 파트너 서비스입니다. 이 실습은 그래서 알림은 SNS와 User Notifications, 티켓은 OpsCenter, 복구는 Automation 런북으로 구성했습니다.

## 회고 질문

1. 실험 시작부터 첫 알람까지 얼마나 걸렸습니까? 그 시간을 줄이려면 어떤 알람의 어떤 값을 바꾸겠습니까?
2. 런북을 원인 제거 전에 실행했다면 무슨 일이 일어났을까요? 그것을 막는 장치를 런북에 넣을 수 있을까요?
3. 카나리 알람과 온콜 알람의 임계값이 다른 이유는 무엇입니까? 같게 하면 어느 쪽이 먼저 문제가 됩니까?
