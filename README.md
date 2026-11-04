# Pyxis

日本のテレビ放送を録画して観るサーバを、Docker の入った Linux 1 台に立てる。
録画と配信は [Carina](https://github.com/NewWorldOrg/Carina)、画面は [Vela](https://github.com/NewWorldOrg/Vela) が受け持つ。
Pyxis はその 2 つを、動作を確かめた版の組で固定して配る。

## 用意するもの

- Docker 25 以上と Docker Compose v2。CPU は amd64
- 録画を置くディスク。地上波の録画は 1 時間に 7 GB ほど
- チューナー。Linux DVB で `/dev/dvb/adapterN` として見える PCIe・USB のカードか、USB の地上デジタルチューナー CECH-ZD1
- B-CAS カードとカードリーダ。ホストで pcscd を動かしておく
- Intel の GPU。無くても動く。録画を H.265 や AV1 にするときと、ライブや再生をその場で変換するときに使う

チューナーもカードも無い機械でも、合成のチューナーで一式を起動して画面を開くところまでは試せる。

## セットアップ

リポジトリを取り、`.env.example` を `.env` に写す。

```bash
git clone https://github.com/NewWorldOrg/Pyxis.git
cd Pyxis
cp .env.example .env
```

`.env` にデータベースのパスワードと、データを置く 4 つのディレクトリを書く。
ディレクトリは空のままでよい。

```bash
mkdir -p /srv/tv/{db,recordings,encodes,keys}
```

| 変数 | 書くもの |
| --- | --- |
| `POSTGRES_PASSWORD` | データベースのパスワード。`;` は使えない |
| `CARINA_DB_DIR` | データベースのデータを置く場所 |
| `CARINA_RECORDINGS_DIR` | 録画を置く場所 |
| `CARINA_ENCODES_DIR` | エンコード済みのファイルを置く場所 |
| `CARINA_KEYS_DIR` | 鍵を置く場所。データベースとは別のディスクか別のバックアップの対象にする |

次に `driver/driver.json` を実機のチューナーに合わせる。
置いてあるのは合成のチューナーの設定で、DVB と USB の見本が `driver/examples/` にある。

```bash
cp driver/examples/driver-dvb.json driver/driver.json
```

`devices` にチューナーごとの `id`・`kind`・`devicePath` を書く。
`kind` は `terrestrial` か `satellite`、`devicePath` は `/dev/dvb/adapter0/frontend0` のように frontend までのパスを書く。
使わないチューナーは `enabled` を `false` にしておく。
ほかのキーは Carina の README の `driver` の節に説明がある。

装置はホストから渡す必要があり、compose の装置の指定は数を変えられないため、装置ごとのファイルを `-f` で重ねる。

```bash
docker compose -f compose.yml -f examples/tuner-dvb.yml up -d
```

| ファイル | 渡すもの |
| --- | --- |
| `examples/tuner-dvb.yml` | `/dev/dvb/adapter0` と、ホストの pcscd の `/run/pcscd` |
| `examples/tuner-usb.yml` | `/dev/bus/usb`。CECH-ZD1 用 |
| `examples/gpu-intel.yml` | `/dev/dri`。Intel の GPU 用 |

チューナーが 2 本以上あるときは、`examples/tuner-dvb.yml` の `devices` に行を足す。
GPU も渡すときは `-f examples/gpu-intel.yml` を続ける。
`.env` に `COMPOSE_FILE=compose.yml:examples/tuner-dvb.yml:examples/gpu-intel.yml` と書いておけば、以後は `docker compose up -d` だけで済む。
何も重ねずに起動すると、合成のチューナーで動く。

起動したら、ブラウザで `http://<機械のアドレス>/` を開く。
最初の起動で `app` がローカルアカウントを作り、ユーザー名とパスワードをログに一度だけ書く。

```bash
docker compose logs app | grep 'Sign in as'
```

そのアカウントでログインしたら、設定の画面でパスワードを変える。
チャンネルのスキャンと受信の確認も設定の画面にある。

## 設定

`.env` の変数は次の 12 個。
空にできない 5 つを空のままにすると、compose は起動せずにその変数の名前を出す。

| 変数 | 用途 | 既定 |
| --- | --- | --- |
| `POSTGRES_PASSWORD` | データベースのパスワード | 必須 |
| `CARINA_DB_DIR` | データベースのデータを置くホスト側のディレクトリ | 必須 |
| `CARINA_RECORDINGS_DIR` | 録画を置くホスト側のディレクトリ。`driver` が書き、`app` は読むだけ | 必須 |
| `CARINA_ENCODES_DIR` | エンコード済みのファイルを置くホスト側のディレクトリ | 必須 |
| `CARINA_KEYS_DIR` | OIDC の client secret を暗号化する鍵を置くホスト側のディレクトリ | 必須 |
| `CARINA_PUBLIC_ORIGIN` | ブラウザから届くアドレス。OIDC でサインインするときに要る | 空 |
| `PYXIS_SITE_ADDRESS` | 前段の Caddy が開くサイトのアドレス。ドメインを書くと証明書を取って https で開く | `:80` |
| `PYXIS_HTTP_PORT` | ホストで開く http のポート | `80` |
| `PYXIS_HTTPS_PORT` | ホストで開く https のポート。TCP と UDP | `443` |
| `CARINA_ENCODINGS_PREFER` | あとからのエンコードに使う変換器。`Software` か `Vaapi` | `Software` |
| `CARINA_TRANSCODING_PREFER` | ライブと再生のその場の変換に使う変換器。`Software` か `Vaapi` | `Software` |
| `CARINA_RENDER_NODE` | VAAPI で使う GPU のノード | `/dev/dri/renderD128` |

番組表を集める間隔や品質の閾値といった細かい設定は、Carina の README の `app` の節にある。
変えたいものがあれば、`compose.override.yml` を置いて `app` の `environment` に書く。
このファイルは `.gitignore` に入っている。

### GPU

`examples/gpu-intel.yml` を重ねただけでは、変換はソフトウェアのまま動く。
GPU で変換させるには `CARINA_ENCODINGS_PREFER` と `CARINA_TRANSCODING_PREFER` を `Vaapi` にする。
GPU が 2 枚あるときは `CARINA_RENDER_NODE` で使う方を選ぶ。

### 外から開く

家の外から開くには、ドメインをこの機械に向けてルータの 80 番と 443 番を通し、`.env` に 2 行を書く。

```
PYXIS_SITE_ADDRESS=tv.example.com
CARINA_PUBLIC_ORIGIN=https://tv.example.com
```

Caddy が Let's Encrypt から証明書を取り、http で来た要求は https へ送る。
`CARINA_PUBLIC_ORIGIN` は OIDC の redirect URI の元になるため、ブラウザが使うアドレスと一致させる。

ホストの 80 番や 443 番をほかのものが使っているときは、`PYXIS_HTTP_PORT` と `PYXIS_HTTPS_PORT` を空いている番号に変える。
ドメインで https にするなら、ルータ側の 80 番と 443 番をその番号へ向ける。

### 前段を自分で持つ

前段のプロキシを自分で持つなら、`proxy` を外して `app` と `vela` を直接受ける。

```yaml
# compose.override.yml
services:
  proxy:
    profiles: [unused]
  app:
    ports: ['127.0.0.1:8080:8080']
  vela:
    ports: ['127.0.0.1:3000:3000']
```

その前段には、同梱の `Caddyfile` がしているのと同じ 5 つを持たせる。

- `/api/*` を `app` の 8080 番へ、それ以外を `vela` の 3000 番へ送り、両方を同じオリジンで開く。オリジンが分かれるとブラウザが Cookie を送らない
- `/api/events` はサーバから流れ続ける応答なので、溜めずに流す
- `/api/live/ws` は WebSocket なので、切らずに通す
- `Range` ヘッダをそのまま通す。再生とシークに使う
- アクセスログを取るなら、パスを残さない。外部プレイヤー向けの URL は、パスに再生用のトークンを含む

あわせて `app` の `environment` に `CARINA_KNOWN_NETWORKS` を足し、前段のアドレスの範囲を書く。
これが無いと `X-Forwarded-*` が読まれず、https で開いてもセッション Cookie に Secure が付かない。

## 更新

Pyxis の新しい版は、`compose.yml` のイメージの版を上げたリリースとして出る。
古い `app` を止めてからデータベースのスキーマを当て、新しい `app` を上げる。
`app` が動いたままスキーマを当てると、列や表を消す変更で古い `app` が壊れる。

```bash
git fetch --tags
git checkout v0.2.0   # 上げたい版のタグ
docker compose pull
docker compose stop app
docker compose up -d
```

`up -d` は `migrate` を先に走らせ、それが成功してから `app` を上げる。
`driver` の版が前と同じなら `driver` は作り直されず、録画は続く。

`driver` の版が変わる更新は、録画中とライブの視聴中を避ける。
録画中の `driver` は録画が終わるまで止まらず、その間は新しい `driver` も上がらない。
待つ上限は `driver.json` の `shutdownGraceHours` で、既定は 6 時間。
ライブの視聴は切れる。

`driver` の入れ替えだけを後に回すこともできる。

```bash
docker compose stop app
docker compose run --rm migrate
docker compose up -d --no-deps app vela proxy
```

`driver` が変わるかどうかと、列や表を消すスキーマの変更があるかどうかは、各リリースの本文にある。

## 戻し方

更新の前に、データベースと鍵の控えを取っておく。

```bash
docker compose exec db pg_dump -U carina -Fc carina > carina-$(date +%Y%m%d).dump
tar -C "$(grep ^CARINA_KEYS_DIR= .env | cut -d= -f2)" -cf keys-$(date +%Y%m%d).tar .
```

戻すときは、前の版のタグに戻してからデータベースを控えから入れ直す。

```bash
docker compose stop app
git checkout v0.1.0
docker compose exec -T db dropdb -U carina carina
docker compose exec -T db createdb -U carina -O carina carina
docker compose exec -T db pg_restore -U carina -d carina < carina-20260101.dump
docker compose up -d
```

スキーマの変更が足すだけだった版なら、データベースはそのままで前の版の `app` を上げれば動く。
どちらかはリリースの本文に書いてある。
録画のファイルはどの版でも同じ場所にあり、戻しても消えない。

## 版

| Pyxis | Carina app | Carina driver | Vela | PostgreSQL | Caddy |
| --- | --- | --- | --- | --- | --- |
| 未リリース | v1.0.0 | v1.0.0 | v1.0.0 | 18.6 | 2.11.7 |

イメージの版は `compose.yml` に数字で書いてあり、`latest` は使わない。
Pyxis の版は、その組で起動・録画・再生を確かめてから付ける。

## ライセンス

AGPL-3.0-only。著作権者は NewWorldOrg で、全文は `LICENSE` にある。

Pyxis が持つのは設定だけで、ソフトウェアは各イメージの側にある。
イメージに同梱した他のソフトウェアとそのライセンスは、イメージの中の `/usr/share/doc/carina/` と `/usr/share/doc/vela/` で読める。
PostgreSQL と Caddy は公式のイメージをそのまま使う。
