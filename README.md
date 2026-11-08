# Pyxis

日本のテレビ放送を録画して視聴するサーバを、Docker の入った Linux 1 台で動かすための構成です。\
チューナーの制御は [Puppis](https://github.com/NewWorldOrg/Puppis)、録画と配信の API は [Carina](https://github.com/NewWorldOrg/Carina)、画面は [Vela](https://github.com/NewWorldOrg/Vela) が受け持ちます。\
Pyxis はこの 3 つを、動作を確認したバージョンの組み合わせで固定して配布します。\
Kubernetes 向けには、同じ組み合わせの Helm チャートが `charts/pyxis` にあります。

ブラウザで番組表から予約し、ライブと録画を視聴し、エンコードと CM・OP・ED のスキップを使えます。\
B-CAS カードを 1 枚しか持っていなくても、別の機械のチューナーにカードを貸せます。

## 必要なもの

- Docker 25 以上と Docker Compose v2。CPU は amd64
- 録画用のディスク。地上波の録画は 1 時間あたり約 7 GB
- チューナー。Linux DVB で `/dev/dvb/adapterN` として見える PCIe・USB のカード、または USB チューナーの CECH-ZD1
- B-CAS カードとカードリーダー。ホストで pcscd を動かしておきます
- Intel の GPU か NVIDIA の GPU(任意)。NVIDIA は NVIDIA Container Toolkit とドライバ 530.41.03 以上が要ります。H.265 と AV1 のエンコード、ライブと再生の変換に使います

チューナーとカードが無い機械でも、合成チューナーで画面を開くところまでは試せます。

## 動かす

```bash
git clone https://github.com/NewWorldOrg/Pyxis.git
cd Pyxis
cp .env.example .env
mkdir -p /srv/tv/{db,recordings,encodes,keys}
```

`.env` にデータベースのパスワードと、データを置く 4 つのディレクトリを書きます。\
次に `driver/driver.json` をチューナーに合わせます。\
DVB と USB のサンプルが `driver/examples/` にあります。

```bash
cp driver/examples/driver-dvb.json driver/driver.json
docker compose -f compose.yml -f examples/tuner-dvb.yml up -d
```

`examples/` のファイルはホストのデバイスをコンテナに渡すもので、USB チューナーなら `tuner-usb.yml`、Intel の GPU なら `gpu-intel.yml`、NVIDIA の GPU なら `gpu-nvidia.yml` を重ねます。\
`.env` に `COMPOSE_FILE=compose.yml:examples/tuner-dvb.yml` と書いておくと、以後は `docker compose up -d` だけで起動します。

起動したら、ブラウザで `http://<サーバのアドレス>/` を開きます。\
初回の起動で app がローカルアカウントを作り、ユーザー名とパスワードをログに 1 回だけ出します。

```bash
docker compose logs app | grep 'Sign in as'
```

ログインしたら、設定画面でパスワードを変え、チャンネルをスキャンしてください。

## 設定

`.env` に書く変数です。

| 変数 | 内容 | 既定 |
| --- | --- | --- |
| `POSTGRES_PASSWORD` | データベースのパスワード。`;` は使えません | 必須 |
| `CARINA_DB_DIR` | データベースのデータを置くディレクトリ | 必須 |
| `CARINA_RECORDINGS_DIR` | 録画を置くディレクトリ | 必須 |
| `CARINA_ENCODES_DIR` | エンコード済みファイルを置くディレクトリ | 必須 |
| `CARINA_KEYS_DIR` | 暗号化鍵を置くディレクトリ。データベースとは別にバックアップします | 必須 |
| `CARINA_PUBLIC_ORIGIN` | ブラウザから見たサーバのアドレス。OIDC でサインインするときに必要です | 空 |
| `PYXIS_SITE_ADDRESS` | Caddy が待ち受けるアドレス。ドメインを書くと証明書を取得して https で開きます | `:80` |
| `PYXIS_HTTP_PORT` / `PYXIS_HTTPS_PORT` | ホスト側で開くポート | `80` / `443` |
| `CARINA_ENCODINGS_PREFER` | エンコードに使うエンコーダー。`Software`・`Vaapi`・`Nvenc` のどれか | `Software` |
| `CARINA_TRANSCODING_PREFER` | ライブと再生の変換に使うエンコーダー。`Software`・`Vaapi`・`Nvenc` のどれか | `Software` |
| `CARINA_RENDER_NODE` | VAAPI で使う GPU のデバイス | `/dev/dri/renderD128` |

番組表の収集間隔や品質の閾値などの細かい設定は Carina の README にあります。\
変えるときは `compose.override.yml` を置き、`app` の `environment` に書きます。

## 更新

```bash
git fetch --tags
git checkout v0.5.0
docker compose pull
docker compose stop app
docker compose up -d
```

`up -d` はデータベースのマイグレーションを実行してから app を起動します。\
driver のバージョンが変わる更新は、録画中とライブの視聴中を避けてください。\
driver は進行中の録画が終わるまで停止を待ちます。

更新の前に、データベースと鍵のバックアップを取っておきます。

```bash
docker compose exec db pg_dump -U carina -Fc carina > carina-$(date +%Y%m%d).dump
tar -C "$(grep ^CARINA_KEYS_DIR= .env | cut -d= -f2)" -cf keys-$(date +%Y%m%d).tar .
```

## Helm

```bash
helm install carina oci://ghcr.io/newworldorg/charts/pyxis --version 0.5.0 -n tv --create-namespace -f values.yaml
```

値の一覧と説明は `charts/pyxis/values.yaml` にあります。\
driver は特権コンテナなので、名前空間の Pod Security は `privileged` にしてください。

## バージョン

| Pyxis | Carina | Puppis | Vela | PostgreSQL | Caddy |
| --- | --- | --- | --- | --- | --- |
| 0.5.0 | v2.0.0 | v0.2.0 | v1.3.0 | 18.6(Debian) | 2.11.7 |
| 0.4.0 | v2.0.0 | v0.1.1 | v1.2.0 | 18.6(Debian) | 2.11.7 |
| 0.3.0 | v2.0.0 | v0.1.1 | v1.1.0 | 18.6(Debian) | 2.11.7 |
| 0.2.0 | v2.0.0 | v0.1.1 | v1.1.0 | 18.6(Alpine) | 2.11.7 |
| 0.1.0 | v2.0.0 | v0.1.1 | v1.0.0 | 18.6(Alpine) | 2.11.7 |

## ライセンス

AGPL-3.0-only です。著作権者は NewWorldOrg で、全文は `LICENSE` にあります。\
各イメージに同梱したソフトウェアのライセンスは、イメージ内の `/usr/share/doc/` にあります。
