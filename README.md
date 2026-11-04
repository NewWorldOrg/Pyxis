# Pyxis

Pyxis は、日本の地上デジタル放送向けの録画システムを立てるための配布用リポジトリである。
バックエンドの [Carina](https://github.com/NewWorldOrg/Carina) と画面の [Vela](https://github.com/NewWorldOrg/Vela) を、確かめた版の組み合わせのまま 1 回の操作で立てる。
イメージは作らず、置いてあるのは設定と版の固定だけである。

## 構成

| 役割 | イメージ | 中身 |
| --- | --- | --- |
| `driver` | `ghcr.io/newworldorg/carina` | 特権で動き、チューナーを占有して録画ファイルを書く |
| `app` | `ghcr.io/newworldorg/carina` | 番組表・予約・ライブ・エンコード・ライブラリの HTTP API |
| `vela` | `ghcr.io/newworldorg/vela` | ブラウザで開く画面 |
| `db` | `postgres` | データベース |
| `proxy` | `caddy` | 前段。`/api/*` を `app` に、それ以外を `vela` に振り分ける |

`driver` と `app` は Unix ドメインソケットで通信する。
別のプロセスなので、`app` を入れ替えても進行中の録画は止まらない。
`app` と `vela` は同じオリジンに置き、振り分けは前段の `proxy` が行う。

版は Pyxis のリリースタグで固定する。
`latest` には頼らず、イメージの版はファイルに数字で書く。

## 必要なもの

- Docker と Docker Compose
- チューナー・カードリーダ・GPU のある Linux の機械 1 台

チューナーが無くても、合成のチューナーで起動だけは試せる。

## ライセンス

ライセンスは AGPL-3.0-only で、著作権者は NewWorldOrg である。
詳細は `LICENSE` にある。

Pyxis が置いているのは設定だけである。
各イメージに同梱した他のソフトウェアとそのライセンスは、イメージの中の `/usr/share/doc/carina/` と `/usr/share/doc/vela/` にある。
PostgreSQL と Caddy は公式のイメージをそのまま引く。
