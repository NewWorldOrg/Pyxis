# Pyxis

日本のテレビ放送(地上デジタルと BS・CS)を録画して観るサーバを、Docker の機械 1 台に立てる。
中身は [Carina](https://github.com/NewWorldOrg/Carina)(録画とライブと API)と [Vela](https://github.com/NewWorldOrg/Vela)(画面)。
Pyxis はこの 2 つを、動く組み合わせの版で固定して配る。

## 用意するもの

- Docker 25 以上と Docker Compose v2 が入った Linux の機械。CPU は amd64
- 録画を置くディスク。地上波は 1 時間で 7 GB ほど増える
- チューナー。Linux DVB 対応のもの(`/dev/dvb/adapterN` が見える PCIe や USB のカード)か、USB の地上デジタルチューナー CECH-ZD1
- B-CAS カードとカードリーダ、ホストで動く pcscd。DVB のチューナーでスクランブルを解くのに使う
- Intel の GPU(任意)。録画をあとから H.265 や AV1 にするときと、ライブや再生をその場で変換するときに使う

チューナーもカードも無くても、合成のチューナーで一式を起動して画面を見るところまでは試せる。

## 立てる

1. このリポジトリを取り、`.env.example` を `.env` に写す。

   ```bash
   git clone https://github.com/NewWorldOrg/Pyxis.git
   cd Pyxis
   cp .env.example .env
   ```

2. `.env` を開き、データベースのパスワードと 4 つのディレクトリを書く。

   ```bash
   mkdir -p /srv/tv/{db,recordings,encodes,keys}
   ```

   | 変数 | 書くもの |
   | --- | --- |
   | `POSTGRES_PASSWORD` | データベースのパスワード。`;` は使えない |
   | `CARINA_DB_DIR` | データベースのデータを置くディレクトリ |
   | `CARINA_RECORDINGS_DIR` | 録画を置くディレクトリ |
   | `CARINA_ENCODES_DIR` | エンコード済みのファイルを置くディレクトリ |
   | `CARINA_KEYS_DIR` | 鍵を置くディレクトリ。データベースとは別の場所にする |

   ディレクトリはどれも空でよい。
   所有者は起動のたびに `prepare` が合わせるので、手で `chown` しなくてよい。

3. チューナーを書く。
   `driver/driver.json` は合成のチューナーの設定なので、実機に合わせて書き換える。
   `driver/examples/` に DVB と USB の見本がある。

   ```bash
   cp driver/examples/driver-dvb.json driver/driver.json
   ```

   `devices` にチューナーごとの `id`・`kind`・`devicePath` を書く。
   `kind` は `terrestrial` か `satellite`。
   DVB なら `/dev/dvb/adapter0/frontend0` のように frontend までを書く。
   使わないチューナーは `enabled` を `false` にする。
   ほかのキーの意味は Carina の README の `driver` の節にある。

4. 装置を渡して起動する。
   compose の装置の指定は数を変えられないので、装置ごとのファイルを `-f` で重ねる。

   ```bash
   docker compose -f compose.yml -f examples/tuner-dvb.yml up -d
   ```

   | 重ねるファイル | 渡すもの |
   | --- | --- |
   | `examples/tuner-dvb.yml` | `/dev/dvb/adapter0` と、ホストの pcscd(`/run/pcscd`) |
   | `examples/tuner-usb.yml` | `/dev/bus/usb`(CECH-ZD1 用) |
   | `examples/gpu-intel.yml` | `/dev/dri`(Intel の GPU) |

   チューナーが 2 本以上なら `examples/tuner-dvb.yml` の `devices` に行を足す。
   GPU も使うなら `-f examples/gpu-intel.yml` を続けて書く。
   毎回 `-f` を書かないなら、`.env` に `COMPOSE_FILE=compose.yml:examples/tuner-dvb.yml:examples/gpu-intel.yml` と書く。
   以後は `docker compose up -d` だけで済む。
   何も重ねなければ、合成のチューナーで起動する。

5. ブラウザで `http://<機械のアドレス>/` を開く。
   最初の起動で `app` がローカルアカウントを作り、ユーザー名とパスワードをログに 1 度だけ書く。

   ```bash
   docker compose logs app | grep 'Sign in as'
   ```

   そのアカウントでログインし、設定の画面でパスワードを変える。
   チャンネルのスキャンと受信の確認は、画面の設定にある。

## 設定

`.env` の変数は次のとおり。
空にできないものは、空のまま `up` すると compose がその名前を挙げて止まる。

| 変数 | 用途 | 既定 |
| --- | --- | --- |
| `POSTGRES_PASSWORD` | データベースのパスワード | 無し。必須 |
| `CARINA_DB_DIR` | データベースのデータを置くホスト側のディレクトリ | 無し。必須 |
| `CARINA_RECORDINGS_DIR` | 録画を置くホスト側のディレクトリ。`driver` が書き、`app` は読むだけ | 無し。必須 |
| `CARINA_ENCODES_DIR` | エンコード済みのファイルを置くホスト側のディレクトリ | 無し。必須 |
| `CARINA_KEYS_DIR` | OIDC の client secret を暗号化する鍵を置くホスト側のディレクトリ | 無し。必須 |
| `CARINA_PUBLIC_ORIGIN` | ブラウザから届くアドレス(`https://tv.example.com`)。OIDC でサインインするときに要る | 空 |
| `PYXIS_SITE_ADDRESS` | 前段の Caddy が開くサイトのアドレス。ドメインを書くと証明書を取って https で開く | `:80` |
| `PYXIS_HTTP_PORT` | ホストで開く http のポート | `80` |
| `PYXIS_HTTPS_PORT` | ホストで開く https のポート(TCP と UDP) | `443` |
| `CARINA_ENCODINGS_PREFER` | あとからのエンコードに使う変換器。`Software` か `Vaapi` | `Software` |
| `CARINA_TRANSCODING_PREFER` | ライブと再生のその場の変換に使う変換器。`Software` か `Vaapi` | `Software` |
| `CARINA_RENDER_NODE` | VAAPI で使う GPU のノード | `/dev/dri/renderD128` |

番組表を集める間隔や品質の閾値のような細かい設定は、Carina の README の `app` の節にある。
足すなら `compose.override.yml` を置いて `app` の `environment` に書く(`.gitignore` 済み)。

### GPU

`examples/gpu-intel.yml` を重ねただけでは、変換はソフトウェアのままになる。
GPU で変換させるには、`.env` の `CARINA_ENCODINGS_PREFER` と `CARINA_TRANSCODING_PREFER` を `Vaapi` にする。
GPU が 2 枚あるときは `CARINA_RENDER_NODE` で使うノードを選ぶ。

### 外から開く

家の外から開くなら、ドメインをこの機械に向けて 80 番と 443 番を通す。
そのうえで `.env` に書く。

```
PYXIS_SITE_ADDRESS=tv.example.com
CARINA_PUBLIC_ORIGIN=https://tv.example.com
```

Caddy が Let's Encrypt から証明書を取り、http は https に送る。
`CARINA_PUBLIC_ORIGIN` は OIDC の redirect URI の元になるので、ブラウザが使うアドレスと同じにする。

### 80 番と 443 番がふさがっているとき

この機械でほかのものが 80 番や 443 番を使っているなら、`.env` の `PYXIS_HTTP_PORT` と `PYXIS_HTTPS_PORT` を別の番号にする。
ドメインで https にするときは、ルータの 80 番と 443 番をその番号に向ける。

### 前段を自分で持つとき

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

自分の前段では次を守る。

- `/api/*` を `app` の 8080 番に、それ以外を `vela` の 3000 番に送る。両方を同じオリジンで開く(分かれると Cookie が届かない)
- `/api/events` はサーバから流れ続ける応答なので、溜めずに流す
- `/api/live/ws` は WebSocket なので、切らずに通す
- `Range` ヘッダをそのまま通す。再生とシークに使う
- アクセスログを取るなら、パスを残さない。外部プレイヤー向けの URL はパスに再生用のトークンを含む

同梱の `Caddyfile` がこの 5 つをしている。
前段を自分で持つときは、`compose.override.yml` の `app` の `environment` に `CARINA_KNOWN_NETWORKS` を足す。
値は前段のアドレスの範囲。
書かないと `X-Forwarded-*` が読まれず、https で開いてもセッション Cookie に Secure が付かない。

## 更新する

Pyxis の新しい版は、`compose.yml` のイメージの版を上げたリリースとして出る。
更新の順は、古い `app` を止める、データベースのスキーマを当てる、新しい `app` を上げる。
`app` が動いたままスキーマを当てると、列や表を消す変更で古い `app` が壊れる。

```bash
git fetch --tags
git checkout v0.2.0   # 上げたい版のタグ
docker compose pull
docker compose stop app
docker compose up -d
```

`up -d` は `migrate` を先に走らせ、成功してから `app` を上げる。
`driver` は `compose.yml` の版が変わらなければ作り直されない。
録画は止まらない。

`driver` の版が変わる更新は、録画中とライブの視聴中を避ける。
録画中に `driver` を止めると、録画が終わるまで待ってから止まる。
待つ上限は `driver.json` の `shutdownGraceHours`(既定 6 時間)で、そのあいだ新しい `driver` は上がらない。
ライブの視聴は切れる。

`driver` の入れ替えを後に回すなら、`driver` を除いて上げる。

```bash
docker compose stop app
docker compose run --rm migrate
docker compose up -d --no-deps app vela proxy
```

その版で `driver` が変わるか、列や表を消すスキーマの変更があるかは、リリースの本文に書く。

## 戻す

更新の前に、データベースと鍵の置き場の控えを取る。

```bash
docker compose exec db pg_dump -U carina -Fc carina > carina-$(date +%Y%m%d).dump
tar -C "$(grep ^CARINA_KEYS_DIR= .env | cut -d= -f2)" -cf keys-$(date +%Y%m%d).tar .
```

戻すときは、前の版に戻してからデータベースを控えから入れ直す。

```bash
docker compose stop app
git checkout v0.1.0
docker compose exec -T db dropdb -U carina carina
docker compose exec -T db createdb -U carina -O carina carina
docker compose exec -T db pg_restore -U carina -d carina < carina-20260101.dump
docker compose up -d
```

スキーマが足すだけの変更だった版なら、データベースを入れ直さずに前の版の `app` を上げるだけで動く。
どちらかはリリースの本文で分かる。

録画のファイルはどの版でも同じ場所にあり、戻しても消えない。

## 版

| Pyxis | Carina app | Carina driver | Vela | PostgreSQL | Caddy |
| --- | --- | --- | --- | --- | --- |
| (未リリース) | v1.0.0 | v1.0.0 | v1.0.0 | 18.6 | 2.11.7 |

イメージの版は `compose.yml` に数字で書いてあり、`latest` は使わない。
Pyxis の版は、この組み合わせで起動と録画と再生を確かめてから付ける。

## ライセンス

Pyxis は AGPL-3.0-only で、著作権者は NewWorldOrg。
全文は `LICENSE` にある。

Pyxis が持つのは設定だけで、ソフトウェアはイメージの側にある。
各イメージに入っている他のソフトウェアとそのライセンスは、イメージの中の `/usr/share/doc/carina/` と `/usr/share/doc/vela/` にある。
PostgreSQL と Caddy は公式のイメージをそのまま使う。
