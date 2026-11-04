{{/*
部品の名前。リリース名に部品の名前をつなぐ (carina-driver、carina-app、carina-db、carina-vela)
*/}}
{{- define "pyxis.partName" -}}
{{- printf "%s-%s" .root.Release.Name .part | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
資源の metadata に付けるラベル。チャートの版はここにだけ入れ、Pod のテンプレートには入れない
*/}}
{{- define "pyxis.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .root.Chart.Name .root.Chart.Version | replace "+" "_" }}
app.kubernetes.io/version: {{ .root.Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
{{ include "pyxis.selectorLabels" . }}
{{- end -}}

{{/*
selector と Pod のテンプレートに使うラベル。作ったあとは変えられない
*/}}
{{- define "pyxis.selectorLabels" -}}
app.kubernetes.io/name: {{ .root.Chart.Name }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .part }}
{{- end -}}

{{/*
部品の nodeSelector。部品のものがあればそれを、無ければ共通のものを使う
*/}}
{{- define "pyxis.nodeSelector" -}}
{{- $selector := .own | default .root.Values.nodeSelector -}}
{{- if $selector }}
nodeSelector:
  {{- toYaml $selector | nindent 2 }}
{{- end }}
{{- end -}}

{{/*
Pod の imagePullSecrets
*/}}
{{- define "pyxis.imagePullSecrets" -}}
{{- with .Values.imagePullSecrets }}
imagePullSecrets:
  {{- range . }}
  - name: {{ . }}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
置き場の volume の中身。type が pvc、existingClaim、hostPath、emptyDir のどれかで形が変わる
*/}}
{{- define "pyxis.volumeSource" -}}
{{- $spec := index .root.Values.persistence .name -}}
{{- if eq $spec.type "pvc" }}
persistentVolumeClaim:
  claimName: {{ include "pyxis.partName" (dict "root" .root "part" .name) }}
{{- else if eq $spec.type "existingClaim" }}
persistentVolumeClaim:
  claimName: {{ required (printf "persistence.%s.existingClaim に PVC の名前を書く" .name) $spec.existingClaim }}
{{- else if eq $spec.type "hostPath" }}
hostPath:
  path: {{ required (printf "persistence.%s.hostPath.path にホスト側のパスを書く" .name) $spec.hostPath.path }}
  type: {{ $spec.hostPath.type | default "Directory" }}
{{- else if eq $spec.type "emptyDir" }}
emptyDir: {}
{{- else }}
{{- fail (printf "persistence.%s.type は pvc、existingClaim、hostPath のどれかにする" .name) }}
{{- end }}
{{- end -}}

{{/*
データベースのパスワードを持つ Secret の名前。existingSecret が無ければチャートが作る Secret
*/}}
{{- define "pyxis.dbSecretName" -}}
{{- .Values.postgres.auth.existingSecret | default (include "pyxis.partName" (dict "root" . "part" "db")) -}}
{{- end -}}

{{/*
app と migrate に渡す接続文字列の環境変数。同梱のときは Service 名とパスワードから組み、外のときは Secret から読む
*/}}
{{- define "pyxis.connectionStringEnv" -}}
{{- if .Values.postgres.enabled }}
- name: PGPASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "pyxis.dbSecretName" . }}
      key: {{ .Values.postgres.auth.passwordKey }}
- name: ConnectionStrings__Carina
  value: {{ printf "Host=%s;Port=5432;Database=%s;Username=%s;Password=$(PGPASSWORD)" (include "pyxis.partName" (dict "root" . "part" "db")) .Values.postgres.auth.database .Values.postgres.auth.username | quote }}
{{- else }}
- name: ConnectionStrings__Carina
  valueFrom:
    secretKeyRef:
      name: {{ required "postgres.enabled が false のときは externalDatabase.connectionSecret に接続文字列を持つ Secret の名前を書く" .Values.externalDatabase.connectionSecret }}
      key: {{ .Values.externalDatabase.connectionKey }}
{{- end }}
{{- end -}}
