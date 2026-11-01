# DevOps 체험하기: 카오스 엔지니어링(AWS FIS)과 온콜 대응(CloudWatch, SNS, OpsCenter)

콘솔 따라하기 (스크린샷 66장)

세션 진행자용. 각 장면은 실제 AWS 콘솔에서 찍은 화면이고, 빨간 박스가 다음에 누를 곳이다.
계정 ID와 이메일, 액세스 키는 화면에서 예시 값으로 바꿔 두었다.
순서는 `docs/guide.ko.md`와 같다. CLI로 하는 쪽이 빠르면 각 단계의 `scripts/*.sh`를 쓰면 된다.

## 0. IAM: 실습용 권한 만들기

관리자 계정이면 건너뛴다. CloudShell을 쓸 사용자가 관리자가 아닐 때만 필요하다.

1. IAM > 정책 > **정책 생성**.
   ![](screenshots/01-iam-policies-create.png)
2. 편집기를 **JSON**으로 바꾼다.
   ![](screenshots/02-iam-policy-json-toggle.png)
3. `iam/lab-policy.json` 내용을 붙여 넣고 **다음**.
   ![](screenshots/03-iam-policy-json-filled.png)
4. 정책 이름 `devops-handson`. (스크린샷에는 이전 이름 `devops-day-lab`이 보인다. 이름만 다르고 순서는 같다.)
   ![](screenshots/04-iam-policy-name.png)
5. **정책 생성**.
   ![](screenshots/05-iam-policy-create-button.png)
6. 생성 확인.
   ![](screenshots/06-iam-policy-created.png)
7. IAM > 사용자 > 실습에 쓸 사용자.
   ![](screenshots/07-iam-users-list.png)
8. **권한 추가** 드롭다운.
   ![](screenshots/08-iam-user-add-permissions.png)
9. 메뉴에서 **권한 추가**.
   ![](screenshots/09-iam-user-add-permissions-menu.png)
10. **직접 정책 연결**.
    ![](screenshots/10-iam-attach-direct-radio.png)
11. `devops-handson` 검색 후 체크.
    ![](screenshots/11-iam-attach-select-policy.png)
12. **다음**.
    ![](screenshots/12-iam-attach-next.png)
13. 검토 화면에서 **권한 추가**.
    ![](screenshots/13-iam-attach-confirm.png)
14. 사용자에 정책이 붙었다.
    ![](screenshots/14-iam-user-permissions-done.png)

## 1. 배포 (CloudShell)

1. 콘솔 상단의 CloudShell 아이콘. 리전은 서울(ap-northeast-2)로 맞춘다.
   ![](screenshots/15-console-home-cloudshell-icon.png)
2. 레포를 받는다.
   ```
   git clone https://github.com/Gosorasora/devops-day-lab.git && cd devops-day-lab && ls
   ```
   ![](screenshots/16-cloudshell-clone-typed.png)
   ![](screenshots/17-cloudshell-clone-done.png)
3. 설치 스크립트. 이메일을 물으면 온콜 메일 주소를 넣는다. SMS는 Enter로 건너뛰어도 된다.
   ```
   ./scripts/setup.sh
   ```
   ![](screenshots/18-cloudshell-setup-typed.png)
4. 끝나면 스택 출력과 대시보드 주소가 나온다. 3분에서 5분 걸린다.
   ![](screenshots/19-cloudshell-setup-done.png)

## 2. 온콜 연결: SNS 구독 확인

1. 메일함에 "AWS Notification - Subscription Confirmation"이 온다. **Confirm subscription**을 누른다.
   ![](screenshots/21-gmail-subscription-mail-list.png)
   ![](screenshots/22-gmail-confirm-subscription-mail.png)
2. SNS > 구독에서 상태가 **확인됨**이면 끝. 이 전까지는 알람이 아무에게도 가지 않는다.
   ![](screenshots/20-sns-subscriptions-confirmed.png)

## 3. 기준선

1. CloudWatch > 대시보드 > `devops-day-lab`. 분당 주문 10건, 오류 0, p95 100 ms 안팎을 눈에 익힌다.
   ![](screenshots/23-cloudwatch-dashboard-baseline.png)
2. CloudWatch > 경보. 다섯 개가 보인다. (아래 화면은 이미 한 번 장애를 겪은 뒤라 DLQ 알람이 켜져 있다. 처음 배포한 상태라면 전부 정상이다.)
   ![](screenshots/24-cloudwatch-alarms-baseline.png)

## 4. 부수기: FIS 실험 시작

1. AWS FIS > 실험 템플릿 > `devops-day-lab-error`.
   ![](screenshots/40-fis-templates-list.png)
2. **실험 시작**.
   ![](screenshots/41-fis-template-start-experiment.png)
3. 태그는 비워 두고 다시 **실험 시작**.
   ![](screenshots/42-fis-start-experiment-page.png)
4. 확인 창에 `시작`을 입력하고 **실험 시작**. 이 시각을 적어 둔다. 장애 시작 시각이다.
   ![](screenshots/43-fis-start-confirm-dialog.png)
5. 상태 **Running**. 4분 동안 모든 주문이 실패한다.
   ![](screenshots/44-fis-experiment-running.png)

## 5. 호출: 알람, 메일, OpsItem

1. 1분에서 2분 뒤 CloudWatch > 경보. `devops-day-lab-consumer-errors`가 **경보 상태**로 바뀐다.
   ![](screenshots/45-cloudwatch-alarms-in-alarm.png)
2. 알람을 열면 임계값(1분에 오류 5건 이상)을 넘은 지점이 보인다.
   ![](screenshots/46-cloudwatch-alarm-consumer-errors-detail.png)
3. 같은 시각 온콜 메일함에 "ALARM: devops-day-lab-consumer-errors"가 온다. 이것이 호출이다.
   ![](screenshots/51-gmail-alarm-mail-list.png)
   ![](screenshots/52-gmail-alarm-mail-body.png)
4. 대시보드. 오류가 호출 수와 같아지고, 잠시 뒤 DLQ가 쌓이기 시작한다.
   ![](screenshots/47-cloudwatch-dashboard-during-outage.png)
5. Systems Manager > OpsCenter. 알람이 OpsItem을 자동으로 만들었다. 심각도 2가 오류 알람, 3이 DLQ 알람이다.
   ![](screenshots/34-opscenter-summary.png)
   ![](screenshots/53-opscenter-opsitems-after-second-outage.png)

## 6. 대응

### 6-1. 장애 끄기 (FIS 중지)

4분을 기다려도 되고, 원인을 찾았다고 치고 바로 끈다.

1. AWS FIS > 실험 > 실행 중인 실험 > **실험 중지**.
   ![](screenshots/48-fis-stop-experiment-button.png)
2. 확인 창에서 다시 **실험 중지**.
   ![](screenshots/49-fis-stop-confirm-dialog.png)
3. 상태가 Stopped로 바뀐다. 다음 주문부터 정상 처리된다.
   ![](screenshots/50-fis-experiment-stopped.png)

### 6-2. 못 보낸 주문 되살리기 (런북)

1. SQS > 대기열. `devops-day-lab-orders-dlq`에 메시지가 남아 있다. 장애 동안 세 번 재시도하고도 실패한 주문들이다.
   ![](screenshots/25-sqs-queues-dlq-has-messages.png)
2. Systems Manager > 자동화 > **자동화 실행**.
   ![](screenshots/26-ssm-automation-execute-button.png)
3. **내 소유** 탭.
   ![](screenshots/27-ssm-automation-owned-by-me-tab.png)
4. `devops-day-lab-redrive-dlq` 선택.
   ![](screenshots/28-ssm-automation-select-runbook.png)
5. **다음**.
   ![](screenshots/29-ssm-automation-next.png)
6. 간편한 실행 그대로 **실행**.
   ![](screenshots/30-ssm-automation-execute.png)
7. 실행 화면. 몇 초 뒤 `redrive` 단계가 **성공**으로 바뀐다.
   ![](screenshots/31-ssm-automation-execution-started.png)
   ![](screenshots/32-ssm-automation-execution-success.png)
8. SQS로 돌아가면 DLQ가 0이다. 되살린 주문은 정상 경로로 다시 처리되어 S3에 쌓인다.
   ![](screenshots/33-sqs-queues-dlq-empty-after-redrive.png)

### 6-3. 티켓 닫기 (OpsItem)

1. OpsCenter > 운영 항목 > OpsItem을 연다. 관련 리소스에 알람과 함수가 달려 있다.
   ![](screenshots/35-opscenter-opsitems-list.png)
   ![](screenshots/36-opscenter-opsitem-detail.png)
2. **상태 설정** > **해결됨**.
   ![](screenshots/37-opscenter-opsitem-set-status.png)
   ![](screenshots/38-opscenter-opsitem-resolved-menu.png)
   ![](screenshots/39-opscenter-opsitem-resolved.png)

## 7. 안전한 배포: 카나리 롤백

1. CloudShell에서 일부러 나쁜 버전을 배포한다.
   ```
   ./scripts/release.sh on
   ```
   ![](screenshots/54-cloudshell-release-on-typed.png)
   ![](screenshots/55-cloudshell-release-on-running.png)
2. CodeDeploy > 배포. 새 배포가 **진행 중**이다.
   ![](screenshots/56-codedeploy-deployments-list.png)
3. 배포 상세. 2단계 트래픽 전환이 10%에서 멈춰 있다. 10분 동안 10%만 새 버전으로 보내는 구성이다.
   ![](screenshots/57-codedeploy-deployment-in-progress.png)
4. Lambda > 별칭 `live`. 버전 1이 90%, 버전 2가 10%.
   ![](screenshots/58-lambda-alias-live-weighted.png)
5. 몇 분 안에 새 버전의 오류가 `devops-day-lab-canary-errors` 알람을 울리고 CodeDeploy가 배포를 멈춘 뒤 자동으로 되돌린다.
   ![](screenshots/59-codedeploy-deployment-stopped-rollback.png)
   ![](screenshots/60-codedeploy-deployments-list-after-rollback.png)
6. CloudShell에도 스택이 `UPDATE_ROLLBACK_COMPLETE`로 돌아온 것이 보인다. 마지막 줄이 "Deploy failed and rolled back. With Bug=on, that is the canary doing its job."이면 성공이다.
   ![](screenshots/61-cloudshell-release-on-rolled-back.png)

## 8. 정리

1. CloudFormation > 스택 > `devops-day-lab`.
   ![](screenshots/62-cloudformation-stacks-list.png)
2. **삭제**. S3 버킷에 주문 파일이 남아 있으면 삭제가 실패하므로, CloudShell에서 `./scripts/teardown.sh`를 쓰는 편이 확실하다. 버킷을 비우고 스택을 지운다.
   ![](screenshots/63-cloudformation-stack-delete-button.png)
   ![](screenshots/64-cloudformation-delete-dialog.png)

## 선택: Console Mobile App 푸시

AWS User Notifications > 알림 구성 생성. 이벤트 규칙은 CloudWatch 알람 상태 변경, 전달 채널에서 Console Mobile App에 로그인한 기기를 고른다. 폰에 앱을 설치하고 같은 계정으로 로그인해 두어야 기기가 목록에 나온다.
![](screenshots/65-user-notifications-create-button.png)
![](screenshots/66-user-notifications-create-config.png)
