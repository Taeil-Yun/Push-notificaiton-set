# Push-notificaiton-set
Push Notification settings
 - Android : FCM
 - iOS : APNs
 ```
 iOS 인증서 발급
 1. 개인 인증서
  - 키체인 접근
  - 상단의 키체인 접근 클릭 후 인증서 지원에서 인증 기관에서 인증서 요청
  - 본인 이메일, 이름 입력 후 디스크에 저장됨 및 본인이 키 쌍 정보 지정 선택
  - 원하는 위치에 저장
  - 키 쌍 정보 = 기본값으로 설정 후 계속 클릭
 2. APNs 만들기
  - https://developer.apple.com/ 접속 및 로그인
  - Certificates, Identifiers & Profiles 섹션에서 Identifiers 클릭 후 APNS 발급받을 APP 클릭
  - Push Notification 설정 후 파일 다운로드
 3. APNs 키 체인 등록
  - 다운받은 파일 더블클릭해서 키체인 등록
 4. p12 파일 생성
  - 인증서와 키 동시 선택
  - 마우스 우 클릭
  - 2개 항목 내보내기 선택
  - 저장할 이름과 위치 지정
  - p12 파일 비밀번호 지정 (중요하니 까먹으면 안되므로 다른곳에 비밀번호 저장 추천)
  - "키체인 접근이(가) 키체인에서 '이름' 키를 내보내려고 합니다" 가 뜨면 mac 비밀번호 입력
  - 키만 선택 후 내보내기
  - 위와 동일 설정
 5. pem 파일 생성하기
  - 터미널 오픈 후 저장한 p12파일 위치로 이동
  - 이동 후 openssl pkcs12 -clcerts -nokeys -out 인증서 파일이름.pem -in 인증서 파일이름.p12 입력 후 설정한 비밀번호 입력 (MAC verified OK가 뜨면서 파일이 생성되면 완료)
  - openssl pkcs12 -nocerts -out 키 파일이름.pem -in 키 파일이름.p12 입력 후 설정한 비밀번호 총 3번 입력 (Verifying - Enter PEM pass phrase:가 뜨면서 파일이 생성되면 완료)
  - openssl rsa -in 키 파일이름.pem -out 키 파일이름-noenc.pem 입력 후 설정한 비밀번호 입력 (파일과 키파일 합치는 작업)
  - cat 인증서 파일이름.pem 키 파일이름-noenc.pem > 원하는 파일이름.pem

 ```
