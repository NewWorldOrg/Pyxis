# Pyxis

日本のテレビ放送を録画して観るサーバを、Docker の入った Linux 1 台に立てる。\
チューナーは [Puppis](https://github.com/NewWorldOrg/Puppis)、録画と配信は [Carina](https://github.com/NewWorldOrg/Carina)、画面は [Vela](https://github.com/NewWorldOrg/Vela) が受け持つ。\
Pyxis はその 3 つを、動作を確かめた版の組で固定して配る。\
Kubernetes に立てるなら、同じ版の組を固定した Helm チャートが `charts/pyxis` にある。

立てると、ブラウザから次のことをする。

- 番組表を見て予約する。キーワードや曜日の条件で自動で予約するルールも作れる
- ライブを観る。録画した番組を再生し、字幕を出す
- 録画を H.264・H.265・AV1 にエンコードする。CM・OP・ED は自動で検出して飛ばせる
- 録画ごとのドロップや受信の状態を見て、壊れた録画を探す
- B-CAS カードを 1 枚だけ持つ家で、別の機械のチューナーにもカードを貸す

## 構成

`docker compose ps` に出るサービスは 7 つ。

| サービス | イメージ | 役割 |
| --- | --- | --- |
| `driver` | Puppis | 特権で動く。チューナーを占有し、スクランブルを解いて録画ファイルを書く |
| `app` | Carina | 番組表・予約・ライブ・エンコード・ライブラリの API。特権は持たない |
| `migrate` | Carina | 起動のたびにデータベースのスキーマを当てて終わる |
| `prepare` | Carina | `app` が書く置き場の所有者を合わせて終わる |
| `vela` | Vela | 画面 |
| `db` | PostgreSQL | データベース |
| `proxy` | Caddy | 前段。`/api/*` を `app` に、それ以外を `vela` に送る |

`driver` と `app` は別のコンテナなので、`app` を入れ替えても録画は止まらない。\
録画ファイルを書くのは `driver` だけで、`app` は読むだけ。

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

`.env` にデータベースのパスワードと、データを置く 4 つのディレクトリを書く。\
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

次に `driver/driver.json` を実機のチューナーに合わせる。\
置いてあるのは合成のチューナーの設定で、DVB と USB の見本が `driver/examples/` にある。

```bash
cp driver/examples/driver-dvb.json driver/driver.json
```

`devices` にチューナーごとの `id`・`kind`・`devicePath` を書く。\
`kind` は `terrestrial` か `satellite`、`devicePath` は `/dev/dvb/adapter0/frontend0` のように frontend までのパスを書く。\
使わないチューナーは `enabled` を `false` にしておく。\
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

チューナーが 2 本以上あるときは、`examples/tuner-dvb.yml` の `devices` に行を足す。\
GPU も渡すときは `-f examples/gpu-intel.yml` を続ける。\
`.env` に `COMPOSE_FILE=compose.yml:examples/tuner-dvb.yml:examples/gpu-intel.yml` と書いておけば、以後は `docker compose up -d` だけで済む。\
何も重ねずに起動すると、合成のチューナーで動く。

起動したら、ブラウザで `http://<機械のアドレス>/` を開く。\
最初の起動で `app` がローカルアカウントを作り、ユーザー名とパスワードをログに一度だけ書く。

```bash
docker compose logs app | grep 'Sign in as'
```

そのアカウントでログインしたら、設定の画面でパスワードを変える。\
チャンネルのスキャンと受信の確認も設定の画面にある。

## 設定

`.env` の変数は次の 12 個。\
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

番組表を集める間隔や品質の閾値といった細かい設定は、Carina の README の `app` の節にある。\
変えたいものがあれば、`compose.override.yml` を置いて `app` の `environment` に書く。\
このファイルは `.gitignore` に入っている。

### GPU

`examples/gpu-intel.yml` を重ねただけでは、変換はソフトウェアのまま動く。\
GPU で変換させるには `CARINA_ENCODINGS_PREFER` と `CARINA_TRANSCODING_PREFER` を `Vaapi` にする。\
GPU が 2 枚あるときは `CARINA_RENDER_NODE` で使う方を選ぶ。

### 外から開く

家の外から開くには、ドメインをこの機械に向けてルータの 80 番と 443 番を通し、`.env` に 2 行を書く。

```
PYXIS_SITE_ADDRESS=tv.example.com
CARINA_PUBLIC_ORIGIN=https://tv.example.com
```

Caddy が Let's Encrypt から証明書を取り、http で来た要求は https へ送る。\
`CARINA_PUBLIC_ORIGIN` は OIDC の redirect URI の元になるため、ブラウザが使うアドレスと一致させる。

ホストの 80 番や 443 番をほかのものが使っているときは、`PYXIS_HTTP_PORT` と `PYXIS_HTTPS_PORT` を空いている番号に変える。\
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

あわせて `app` の `environment` に `CARINA_KNOWN_NETWORKS` を足し、前段のアドレスの範囲を書く。\
これが無いと `X-Forwarded-*` が読まれず、https で開いてもセッション Cookie に Secure が付かない。

## Helm で立てる

Kubernetes に立てるなら、`charts/pyxis` のチャートを使う。\
compose と同じイメージの版を固定していて、driver・app・画面・データベースを部品ごとに有効と無効を切り替えられる。\
チャートはまだ公開先に置いていないので、リポジトリを取って `charts/pyxis` のパスを渡す。

driver は特権で動き、チューナーと pcscd のソケットをホストから受けるので、名前空間の Pod Security を privileged にしておく。

```bash
kubectl create namespace tv
kubectl label namespace tv pod-security.kubernetes.io/enforce=privileged
```

driver と app はソケットのディレクトリをホストのパスで共有するので、同じノードに置く。\
ノードが複数なら `nodeSelector` にチューナーのあるノードを書く。

値のファイルに、チューナー・置き場・前段・ブラウザから届くアドレスを書く。\
データベースのパスワードは Secret に置き、その名前を `postgres.auth.existingSecret` に書く。

```yaml
# values.yaml
nodeSelector:
  kubernetes.io/hostname: node-1
driver:
  config:
    outputRoots:
      - name: primary
        path: /srv/recordings
    tuner:
      backend: dvb
    devices:
      - id: adapter0.frontend0
        kind: terrestrial
        devicePath: /dev/dvb/adapter0/frontend0
  hostDevices:
    - /dev/dvb/adapter0
  pcscd:
    enabled: true
app:
  publicOrigin: https://tv.example.com
  knownNetworks:
    - 10.42.0.0/16
postgres:
  auth:
    existingSecret: pyxis-db
route:
  kind: ingressRoute
  host: tv.example.com
persistence:
  recordings:
    type: hostPath
    hostPath:
      path: /srv/pyxis/recordings
```

```bash
kubectl -n tv create secret generic pyxis-db --from-literal=password=...
helm install carina charts/pyxis -n tv -f values.yaml
```

リリース名は資源の名前の頭になり、`carina` なら `carina-driver`・`carina-app`・`carina-db`・`carina-vela` になる。\
app は起動のたびに初期化コンテナでデータベースのスキーマを当て、古い app が止まってから当たる。\
ローカルアカウントのパスワードは app のログに 1 度だけ出る。

```bash
kubectl -n tv logs deploy/carina-app -c app | grep 'Sign in as'
```

何も書かずに入れると、合成のチューナー・同梱のデータベース・GPU なし・標準の Ingress で動く。\
そのときもデータベースのパスワードだけは要り、無ければチャートは描画を止める。

### 値

主な値は次のとおりで、全部の値と説明は `charts/pyxis/values.yaml` にある。

| 値 | 用途 | 既定 |
| --- | --- | --- |
| `nodeSelector` | 全部の Pod に当てる nodeSelector。部品ごとの `driver.nodeSelector` などで上書きできる | 空 |
| `carina.uid` / `carina.gid` | app を動かす番号。gid は driver の `socketGroupId` にも入る | `10001` |
| `driver.enabled` / `app.enabled` / `vela.enabled` / `postgres.enabled` | その部品を作るか | `true` |
| `driver.image.tag` / `app.image.tag` / `vela.image.tag` / `postgres.image.tag` | イメージの版。compose と同じ数字で固定してある | 版の表のとおり |
| `driver.config` | `driver.json` の中身をそのまま書く。`socketGroupId` はチャートが入れる | 合成のチューナー |
| `driver.hostDevices` | ホストの装置のディレクトリの一覧。同じパスで driver に渡す | 空 |
| `driver.pcscd.enabled` | ホストの `/run/pcscd` を読み取り専用で渡すか | `false` |
| `driver.socket.hostPath` | driver と app が共有するソケットのディレクトリのホスト側のパス | `/run/pyxis` |
| `driver.hostNetwork` | ホストのネットワークで動かすか。カードを貸す driver は `true` | `false` |
| `driver.lendingKey.existingSecret` | カードの貸し借りの鍵を持つ Secret。`/etc/puppis/lending.key` に所有者だけが読める形で置く | 空 |
| `driver.terminationGracePeriodSeconds` | 止めるときに録画の終わりを待つ秒数。`shutdownGraceHours` より長くする | `25200` |
| `app.publicOrigin` | ブラウザから届くアドレス。OIDC でサインインするときに要る | 空 |
| `app.knownNetworks` | `X-Forwarded-*` を信じる前段の網の一覧。Ingress のコントローラの Pod がいる網を書く | 空 |
| `app.encodingsPrefer` / `app.transcodingPrefer` | 変換器。`Software` か `Vaapi` | `Software` |
| `app.gpu.mode` | GPU の渡し方。`none`、`devicePlugin`、`hostPath` | `none` |
| `app.gpu.resource` | device plugin に要求する資源の名前 | `gpu.intel.com/i915` |
| `app.gpu.renderNode` | VAAPI で使う GPU の描画ノード | `/dev/dri/renderD128` |
| `app.dataProtection.seedSecret` | 鍵の種を持つ Secret。鍵の置き場が空のときだけ写す | 空 |
| `app.extraEnv` | app に足す環境変数の一覧。Carina の README の `app` の節の設定に使う | 空 |
| `postgres.auth.existingSecret` / `postgres.auth.passwordKey` | パスワードを持つ Secret とそのキー | 空 / `password` |
| `postgres.auth.password` | Secret を名指ししないときに、チャートが作る Secret に入れるパスワード | 空 |
| `externalDatabase.connectionSecret` / `externalDatabase.connectionKey` | 同梱のデータベースを使わないときの、接続文字列を持つ Secret とそのキー | 空 / `connection` |
| `route.kind` | 前段の種類。`ingress`、`ingressRoute`、`none` | `ingress` |
| `route.host` | ブラウザが開くホスト名。空なら全部を受ける | 空 |
| `route.ingress.className` / `route.ingress.annotations` / `route.ingress.tls` | 標準の Ingress の設定 | 空 |
| `route.ingressRoute.entryPoints` / `route.ingressRoute.tls` | Traefik の IngressRoute の設定。`tls` を `null` にすると http | `websecure` / `{}` |
| `persistence.<置き場>.type` | `recordings`・`encodes`・`thumbnails`・`captions`・`keys`・`db` の置き方。`pvc`、`existingClaim`、`hostPath` | `pvc` |
| `<部品>.resources` | 部品ごとの resources | 空 |

### 置き場

置き場ごとに `type` を選ぶ。\
`pvc` は PVC を作り、リリースを消しても残す。\
`existingClaim` は手で作った PVC を使う。\
`hostPath` はホストのディレクトリで、無ければ起動しない。\
サムネイルと字幕は `emptyDir` も選べ、Pod と一緒に消えて作り直される。

録画は driver が書き、app は読み取り専用で同じ実体を見る。\
2 つは同じノードに置くので、ReadWriteOnce の PVC でよい。\
鍵の置き場はデータベースとは別のバックアップの対象にする。

### Helm での GPU

Intel の GPU をクラスタの device plugin で渡すなら `app.gpu.mode` を `devicePlugin` にする。\
device plugin はクラスタ全体のものなので、チャートには入っていない。\
device plugin が作る装置は app のユーザーが開けない。\
そのため app は root で始まり、装置のグループを app のものに替えてから権限を落とす。\
`hostPath` は `/dev/dri` をディレクトリごと渡す形で、装置を開くために app を特権にするので、device plugin のほうを勧める。\
どちらも渡しただけでは変換はソフトウェアのままで、`app.encodingsPrefer` と `app.transcodingPrefer` を `Vaapi` にする。

### Helm での前段

`ingress` は Ingress を 1 つ作り、`/api` を app に、それ以外を画面に送る。\
`ingressRoute` は Traefik の IngressRoute を作り、同じ振り分けをする。\
Traefik は SSE と WebSocket を既定で溜めずに通す。\
ingress-nginx なら `route.ingress.annotations` に `nginx.ingress.kubernetes.io/proxy-buffering: "off"` と、`proxy-read-timeout` を長くする行を書く。

`none` は何も作らず、自前の前段に app の Service の 8080 番と画面の Service の 3000 番を向ける。\
その前段には「前段を自分で持つ」の 5 つを持たせる。\
どの形でも、前段の Pod がいる網を `app.knownNetworks` に書く。

### driver だけを立てる

カードを貸す機械には driver だけを入れる。\
app・画面・データベースを作らず、ホストのネットワークで口を開き、鍵を Secret から渡す。

```yaml
driver:
  hostNetwork: true
  config:
    outputRoots:
      - name: primary
        path: /srv/recordings
    tuner:
      backend: dvb
    devices:
      - id: adapter0.frontend0
        kind: terrestrial
        devicePath: /dev/dvb/adapter0/frontend0
    cardLending:
      lend:
        address: 0.0.0.0
        hostNames:
          - lender.example.com
        keyFile: /etc/puppis/lending.key
  hostDevices:
    - /dev/dvb/adapter0
  pcscd:
    enabled: true
  lendingKey:
    existingSecret: pyxis-lending-key
app:
  enabled: false
vela:
  enabled: false
postgres:
  enabled: false
route:
  kind: none
```

```bash
openssl rand -base64 48 > lending.key
kubectl -n tv create secret generic pyxis-lending-key --from-file=key=lending.key
```

借りる側の driver は `config` に `cardLending.borrow` を書き、同じ Secret を渡す。\
貸し借りのキーは Carina の README の `driver` の節にある。

### Helm での更新と戻し方

新しい版のチャートを `helm upgrade carina charts/pyxis -n tv -f values.yaml` で当てる。\
app は古いものが止まってから新しいものが上がり、そのときにスキーマを当てるので、列や表を消す変更でも古い app を壊さない。\
driver のイメージの版が前と同じなら driver は作り直されず、録画は続く。\
driver の版が変わる更新は、「更新」の節と同じく録画中とライブの視聴中を避ける。

控えは compose と同じ `pg_dump` で取る。

```bash
kubectl -n tv exec sts/carina-db -- pg_dump -U carina -Fc carina > carina-$(date +%Y%m%d).dump
```

戻すときは `helm rollback` で前の版のチャートに戻してから、「戻し方」の節と同じ手順でデータベースを入れ直す。\
PostgreSQL のメジャーの版上げは `pg_dump` と `pg_restore` が要り、チャートは自動ではやらない。

## 更新

Pyxis の新しい版は、`compose.yml` のイメージの版を上げたリリースとして出る。\
古い `app` を止めてからデータベースのスキーマを当て、新しい `app` を上げる。\
`app` が動いたままスキーマを当てると、列や表を消す変更で古い `app` が壊れる。

```bash
git fetch --tags
git checkout v0.2.0   # 上げたい版のタグ
docker compose pull
docker compose stop app
docker compose up -d
```

`up -d` は `migrate` を先に走らせ、それが成功してから `app` を上げる。\
`driver` の版が前と同じなら `driver` は作り直されず、録画は続く。

`driver` の版が変わる更新は、録画中とライブの視聴中を避ける。\
録画中の `driver` は録画が終わるまで止まらず、その間は新しい `driver` も上がらない。\
待つ上限は `driver.json` の `shutdownGraceHours` で、既定は 6 時間。\
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

スキーマの変更が足すだけだった版なら、データベースはそのままで前の版の `app` を上げれば動く。\
どちらかはリリースの本文に書いてある。\
録画のファイルはどの版でも同じ場所にあり、戻しても消えない。

## 困ったとき

```bash
docker compose ps
docker compose logs app
docker compose logs driver
```

| 症状 | 見るところ |
| --- | --- |
| `proxy` が上がらず `address already in use` と出る | ホストの 80 番か 443 番をほかのものが使っている。`PYXIS_HTTP_PORT` と `PYXIS_HTTPS_PORT` を変える |
| `up` が変数の名前を出して止まる | `.env` のその変数が空 |
| `driver` のログに `No smart-card reader is attached` と出る | ホストで pcscd が動いていないか、カードリーダがつながっていない。`systemctl status pcscd` で確かめる |
| `driver` のログに `could not be opened` と出る | `examples/tuner-dvb.yml` の `devices` と `driver/driver.json` の `devicePath` が合っていない。ホストで `ls /dev/dvb` を見る |
| 録画がスクランブルされたまま | カードリーダにカードが入っていないか、pcscd がカードを見失っている。pcscd を起動し直す |
| ログインのパスワードが分からない | `docker compose logs app \| grep 'Sign in as'`。2 回目以降の起動では書かれない |
| 画面は開くがライブも再生も始まらない | 前段を自分で持っているなら、`/api/live/ws` と `Range` が通っているか。`CARINA_KNOWN_NETWORKS` も確かめる |

## 版

| Pyxis | Carina | Puppis | Vela | PostgreSQL | Caddy |
| --- | --- | --- | --- | --- | --- |
| 未リリース | v2.0.0 | v0.1.1 | v1.0.0 | 18.6 | 2.11.7 |

イメージの版は `compose.yml` と `charts/pyxis/values.yaml` に数字で書いてあり、`latest` は使わない。\
2 か所が同じ版であることは CI が確かめる。\
Pyxis の版は、その組で起動・録画・再生を確かめてから付ける。

## ライセンス

AGPL-3.0-only。著作権者は NewWorldOrg で、全文は `LICENSE` にある。

Pyxis が持つのは設定だけで、ソフトウェアは各イメージの側にある。\
イメージに同梱した他のソフトウェアとそのライセンスは、イメージの中の `/usr/share/doc/puppis/`・`/usr/share/doc/carina/`・`/usr/share/doc/vela/` で読める。\
PostgreSQL と Caddy は公式のイメージをそのまま使う。
