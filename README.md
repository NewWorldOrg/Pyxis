# Pyxis

Pyxis は、日本の地上デジタル放送向けの録画システムを立てるための配布用リポジトリである。
バックエンドの [Carina](https://github.com/NewWorldOrg/Carina) と画面の [Vela](https://github.com/NewWorldOrg/Vela) を、確かめた版の組み合わせのまま 1 回の操作で立てる。
イメージは作らず、置いてあるのは設定と版の固定だけである。

## 構成

| 役割 | イメージ | 中身 |
| --- | --- | --- |
| `driver` | `ghcr.io/newworldorg/carina` | 特権で動き、チューナーを占有して録画ファイルを書く |
| `app` | `ghcr.io/newworldorg/carina` | 番組表・予約・ライブ・エンコード・ライブラリの HTTP API |
| `migrate` | `ghcr.io/newworldorg/carina` | スキーマを適用して終わる。`app` はこれが成功してから上がる |
| `prepare` | `ghcr.io/newworldorg/carina` | `app` が書く置き場の所有者を `app` の uid にそろえて終わる |
| `vela` | `ghcr.io/newworldorg/vela` | ブラウザで開く画面 |
| `db` | `postgres` | データベース |
| `proxy` | `caddy` | 前段。`/api/*` を `app` に、それ以外を `vela` に振り分ける |

`driver` と `app` は Unix ドメインソケットで通信する。
別のプロセスなので、`app` を入れ替えても進行中の録画は止まらない。
録画ファイルを書くのは `driver` だけで、`app` は読み取り専用で参照する。
`app` と `vela` は同じオリジンに置き、振り分けは前段の `proxy` が担う。

版は Pyxis のリリースタグで固定する。
`latest` には頼らず、イメージの版は `compose.yml` に数字で書く。

```
compose.yml        1 台に全部を立てる compose
.env.example       .env の雛形
Caddyfile          前段のプロキシの設定
driver/            driver.json(合成のチューナー)と、DVB・USB のチューナーの見本
examples/          compose に重ねる装置ごとのファイル
```

## 必要なもの

- Docker と Docker Compose
- チューナー・カードリーダ・GPU のある Linux の機械 1 台

チューナーが無くても、合成のチューナーで起動だけは試せる。

## 立て方

```bash
git clone https://github.com/NewWorldOrg/Pyxis.git
cd Pyxis
cp .env.example .env
```

`.env` にデータベースのパスワードと、データベース・録画・エンコード済みファイル・鍵を置くディレクトリを書く。
どれも空のままでは起動しない。
ディレクトリは無ければ作られ、`app` が書く置き場は `prepare` が所有者を uid 10001 に替える。
中のファイルには触らない。
録画の置き場は `driver` が root で書くので、所有者はそのままでよい。

```bash
docker compose up -d
```

`driver/driver.json` はそのままなら合成のチューナーで動く。
実機のチューナーを使うときは、下の「装置の重ね方」のとおりに `driver.json` と重ねるファイルを用意してから上げる。

初回の起動で `app` がローカルアカウントを 1 つ作り、ユーザー名とパスワードを 1 度だけログに書く。

```bash
docker compose logs app | grep 'Sign in as'
```

ブラウザで `http://<この機械のアドレス>/` を開き、そのアカウントでログインしてからパスワードを替える。

`docker compose ps` の health は、`driver` では `--probe` の結果、`app` では `/api/health`、`vela` では `/login` の応答を表す。
コンテナのログは json-file 形式で、1 ファイル 20 MB・5 世代までに抑える。

### ポートと公開のアドレス

`proxy` はホストの 80 番と 443 番で待つ。
ほかのものが使っているなら、`.env` の `PYXIS_HTTP_PORT` と `PYXIS_HTTPS_PORT` で別の番号にする。

LAN の中だけで使うなら `PYXIS_SITE_ADDRESS` は `:80` のままでよく、http で開く。
公開のドメインがあるなら `PYXIS_SITE_ADDRESS=tv.example.com` のように書く。
Caddy が証明書を取って https で開き、http は https へ転送する。
証明書を取るには、そのドメインがこの機械を指し、インターネットから 80 番と 443 番が届く必要がある。
ホストの番号を変えたときは、ルータで 80 番と 443 番をその番号へ転送する。

どちらの形でも、ブラウザから届くアドレスを `CARINA_PUBLIC_ORIGIN` に書く(`http://192.168.1.10` や `https://tv.example.com`)。
ID プロバイダに登録する redirect URI の元になる。

`proxy` が `app` の前段にいるので、`app` は compose の網からの `X-Forwarded-*` を信じる。
網の範囲は `compose.yml` の `networks` と `CARINA_KNOWN_NETWORKS` に同じ値(`172.30.0.0/24`)で書いてある。
家の網と重なるなら、両方を同じ値で書き換える。

### 止め方

```bash
docker compose stop     # 止める。データは残る
docker compose down     # コンテナと網を消す。データは残る
```

`down -v` はボリュームごと消す。
`driver` と `app` のソケットのほか、サムネイル・字幕・Caddy の証明書がボリュームにあるので、普段は使わない。
`driver` は録画中に止められると、録画が終わるまで(上限 6 時間)待ってから止まる。

## 装置の重ね方

compose の `devices:` は変数で数を変えられないので、装置ごとのファイルを重ねる。

| ファイル | 渡すもの |
| --- | --- |
| `examples/tuner-dvb.yml` | `/dev/dvb/adapter0` と、ホストの pcscd の `/run/pcscd`(読み取り専用) |
| `examples/tuner-usb.yml` | `/dev/bus/usb` |
| `examples/gpu-intel.yml` | `/dev/dri` を `app` に |

```bash
docker compose -f compose.yml -f examples/tuner-dvb.yml -f examples/gpu-intel.yml up -d
```

毎回書かずに済ませるなら、`.env` に `COMPOSE_FILE=compose.yml:examples/tuner-dvb.yml:examples/gpu-intel.yml` を書く。

### DVB のチューナー

`driver/examples/driver-dvb.json` を `driver/driver.json` に写し、`devices` にチューナーを書く。
アダプタが増えたら、`examples/tuner-dvb.yml` の `devices` にも同じアダプタを足す。
B-CAS カードはホストの pcscd で読むので、ホストで pcscd を動かしておく。
`driver.json` のキーは Carina の README の「設定」にある。

### USB のチューナー

`driver/examples/driver-usb.json` を `driver/driver.json` に写す。
チューナーの id はつないだポートから付く(`usb1-1` など)。
`driver` は `/dev/bus/usb` を直に動かすので、ノードの番号が変わっても設定はそのままでよい。

### Intel の GPU

`examples/gpu-intel.yml` を重ねると `/dev/dri` が `app` に渡る。
描画ノードの所有グループは、イメージの entrypoint が装置から読んで `app` に足すので、`group_add` は要らない。
渡しただけでは変換はソフトウェアのままなので、`.env` で `CARINA_ENCODINGS_PREFER` と `CARINA_TRANSCODING_PREFER` を `Vaapi` にする。
描画ノードが `/dev/dri/renderD128` でなければ `CARINA_RENDER_NODE` で指す。

## 移行

現行の録画システムから録画を引き継ぐなら、`CARINA_RECORDINGS_DIR` を移行元と同じマウントの下に置く。
録画はハードリンクで移すので、マウントをまたぐと 1 本も移せない。
手順は Carina の README の「移行」にある。

## 更新

Pyxis のリリースタグが、イメージの版の組み合わせを固定する。
更新は、タグを取り出してから `app` を止め、スキーマを当て、上げ直す順で進める。

```bash
git fetch --tags
git checkout vX.Y.Z
docker compose pull
docker compose stop app
docker compose up -d
```

`up -d` は、古い `app` が止まった状態で `migrate` を走らせ、成功してから新しい `app` を上げる。
列や表を消す migration があっても、動いている古い `app` を壊さない。
`up -d` が作り直すのは定義の変わったサービスだけなので、`driver` のタグが前と同じなら `driver` は動いたままで、録画は止まらない。

`driver` のタグが変わる更新では、`up -d` が `driver` も作り直す。
`driver` は録画が終わるまで止まらないので、録画・視聴・直近の予約が無い時間に当てる。
`driver` だけを後回しにするなら、次のとおり `app` と画面だけを入れ替える。

```bash
docker compose stop app
docker compose run --rm migrate
docker compose up -d --no-deps app vela proxy
```

更新の前に、データベースと鍵の控えを取っておく。

```bash
docker compose exec db pg_dump -U carina carina > carina-$(date +%Y%m%d).sql
cp -a "$CARINA_KEYS_DIR" keys-$(date +%Y%m%d)
```

## 戻し方

`migrate` は進める方向にしか当てないので、戻すときはデータベースを更新前の控えから戻す。

```bash
git checkout vX.Y.Z              # 戻す先のタグ
docker compose stop app
docker compose exec -T db psql -U carina -d postgres -c 'DROP DATABASE carina' -c 'CREATE DATABASE carina OWNER carina'
docker compose exec -T db psql -U carina -d carina < carina-YYYYMMDD.sql
docker compose up -d
```

鍵の置き場は更新で変わらないので、控えから戻すのは中身を失ったときだけでよい。
録画とエンコード済みファイルは戻さない。

## 自前のプロキシを使う

同梱の `proxy` の代わりに自前のプロキシを使うなら、`compose.override.yml`(コミットしない)で `proxy` を外し、`app` と `vela` のポートをこの機械の内側だけに開く。

```yaml
services:
  proxy:
    profiles: [unused]
  app:
    ports:
      - '127.0.0.1:8080:8080'
  vela:
    ports:
      - '127.0.0.1:3000:3000'
```

自前のプロキシは、同じオリジンで `/api/*` を `app` に、それ以外を `vela` に送る。
WebSocket(`/api/live/ws`)と SSE(`/api/events`)は切らずにバッファせず流し、`Range` ヘッダはそのまま通す。
アクセスログを取るならパスを残さない。
外部プレイヤーの URL はパスに再生用のトークンを含む。
プロキシがこの機械の上で動くなら、`app` には compose の網のアドレスから届くので、`CARINA_KNOWN_NETWORKS` はそのままでよい。

## 版の表

| Pyxis | carina(app・migrate) | carina(driver) | vela | postgres | caddy |
| --- | --- | --- | --- | --- | --- |
| master | `app-v1.0.0` | `driver-v1.0.0` | `v1.0.0` | `18.6-alpine` | `2.11.7-alpine` |

## ライセンス

ライセンスは AGPL-3.0-only で、著作権者は NewWorldOrg である。
詳細は `LICENSE` にある。

Pyxis が置いているのは設定だけである。
各イメージに同梱した他のソフトウェアとそのライセンスは、イメージの中の `/usr/share/doc/carina/` と `/usr/share/doc/vela/` にある。
PostgreSQL と Caddy は公式のイメージをそのまま引く。
