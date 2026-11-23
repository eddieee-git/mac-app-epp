#!/bin/zsh
# 이 Mac에서만 쓰는 코드 서명 인증서("Epp Local Signing")를 만들어 로그인 키체인에 넣는다. 한 번만 실행한다.
# Apple 계정은 필요 없다. 이 인증서로 서명하면 macOS가 "이 인증서로 서명한 Epp"만 Epp로 인정한다
# (번들 ID만 같은 다른 프로그램이 Epp의 손쉬운 사용·화면 기록 권한을 이어받지 못한다).
#
# 백업: ~/.config/epp/codesign.p12 (+ 암호 codesign.p12.pass). 업데이트 서명 키와 같은 폴더라 그 폴더를 통째로 백업한다.
# 잃어버리면 새 인증서로 서명한 Epp는 다른 앱으로 보여, 권한을 다시 허용해야 한다.
# 다른 Mac에서 쓰려면: security import ~/.config/epp/codesign.p12 -k ~/Library/Keychains/login.keychain-db -P "$(cat …pass)" -T /usr/bin/codesign
#
# 만든 뒤 macOS가 이 인증서를 믿게 하는 명령(아래 마지막 줄 안내)은 사용자가 직접 실행한다(암호를 물어봄).
set -e
name="Epp Local Signing"
backup_dir="$HOME/.config/epp"
if security find-certificate -c "$name" >/dev/null 2>&1; then
    echo "이미 있어요: $name"
    exit 0
fi

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cat > "$dir/cert.conf" <<CONF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $name
[ ext ]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
CONF

openssl req -x509 -newkey rsa:3072 -nodes -days 7300 -config "$dir/cert.conf" \
    -keyout "$dir/key.pem" -out "$dir/cert.pem" 2>/dev/null
pass=$(openssl rand -hex 24)
# macOS 키체인은 옛 형식(-legacy) p12만 읽는다.
openssl pkcs12 -export -legacy -inkey "$dir/key.pem" -in "$dir/cert.pem" -name "$name" \
    -out "$dir/cert.p12" -passout "pass:$pass" 2>/dev/null
security import "$dir/cert.p12" -k ~/Library/Keychains/login.keychain-db -P "$pass" -T /usr/bin/codesign >/dev/null

mkdir -p "$backup_dir"
chmod 700 "$backup_dir"
umask 077
cp "$dir/cert.p12" "$backup_dir/codesign.p12"
print -rn -- "$pass" > "$backup_dir/codesign.p12.pass"

echo "만들었어요: $name"
echo "백업: $backup_dir/codesign.p12 (+ .pass) — 업데이트 서명 키와 함께 따로 백업해 주세요."
echo "이제 macOS가 이 인증서를 믿게 하려면 직접 실행해 주세요(로그인 암호를 물어요):"
echo "  security find-certificate -c \"$name\" -p > /tmp/epp-cert.pem && security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db /tmp/epp-cert.pem"
