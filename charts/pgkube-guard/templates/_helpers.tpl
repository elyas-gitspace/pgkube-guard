{{/* Chart name */}}
{{- define "pgkube-guard.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* Fully qualified app name, used as prefix for every resource */}}
{{- define "pgkube-guard.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else if contains (include "pgkube-guard.name" .) .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name (include "pgkube-guard.name" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/* Common labels */}}
{{- define "pgkube-guard.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{ include "pgkube-guard.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/* Selector labels */}}
{{- define "pgkube-guard.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pgkube-guard.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "pgkube-guard.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "pgkube-guard.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/* Secret names: the user's existing Secret, or the one created by the chart */}}
{{- define "pgkube-guard.postgresSecretName" -}}
{{- default (printf "%s-postgres" (include "pgkube-guard.fullname" .)) .Values.postgres.existingSecret }}
{{- end }}

{{- define "pgkube-guard.s3BackupSecretName" -}}
{{- default (printf "%s-s3-backup" (include "pgkube-guard.fullname" .)) .Values.storage.s3.backupCredentials.existingSecret }}
{{- end }}

{{/* Secret S3 en lecture seule, partagé par le freshness check et le restore drill */}}
{{- define "pgkube-guard.s3VerifySecretName" -}}
{{- default (printf "%s-s3-verify" (include "pgkube-guard.fullname" .)) .Values.storage.s3.verifyCredentials.existingSecret }}
{{- end }}

{{- define "pgkube-guard.notificationsSecretName" -}}
{{- default (printf "%s-notifications" (include "pgkube-guard.fullname" .)) .Values.notifications.existingSecret }}
{{- end }}

{{/* Réglages communs à tous les pods. Appel : include "pgkube-guard.podSpecCommon" (dict "root" . "securityContext" <contexte de sécu du pod>) */}}
{{- define "pgkube-guard.podSpecCommon" -}}
{{- $root := .root -}}
restartPolicy: Never
serviceAccountName: {{ include "pgkube-guard.serviceAccountName" $root }}
automountServiceAccountToken: false
{{- with .securityContext }}
securityContext:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $root.Values.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $root.Values.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $root.Values.affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/* Identifiants AWS en variables d'env, lus dans un Secret. Appel : (dict "secretName" <nom> "creds" <bloc de credentials des values>) */}}
{{- define "pgkube-guard.awsEnv" -}}
- name: AWS_ACCESS_KEY_ID
  valueFrom:
    secretKeyRef:
      name: {{ .secretName }}
      key: {{ .creds.secretKeys.accessKeyId }}
- name: AWS_SECRET_ACCESS_KEY
  valueFrom:
    secretKeyRef:
      name: {{ .secretName }}
      key: {{ .creds.secretKeys.secretAccessKey }}
- name: HOME
  value: /tmp
{{- end }}

{{/* Labels du template de pod d'un job. Appel : include "pgkube-guard.podMetadata" (dict "root" . "component" "backup") */}}
{{- define "pgkube-guard.podMetadata" -}}
labels:
  {{- include "pgkube-guard.selectorLabels" .root | nindent 2 }}
  app.kubernetes.io/component: {{ .component }}
  {{- with .root.Values.podLabels }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- with .root.Values.podAnnotations }}
annotations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/* Vérifie que les values sont cohérentes, et arrête l'install avec un message clair sinon */}}
{{- define "pgkube-guard.validate" -}}
{{- $src := .Values.verify.source -}}
{{- if not (has $src (list "pgdump" "walg")) -}}
{{- fail (printf "verify.source must be 'pgdump' or 'walg', got '%s'" $src) -}}
{{- end -}}
{{- if and .Values.backup.enabled (ne $src "pgdump") -}}
{{- fail "backup.enabled=true produces pg_dump files: set verify.source=pgdump, or backup.enabled=false if your backups come from wal-g" -}}
{{- end -}}
{{- if .Values.backup.enabled -}}
{{- $_ := required "postgres.host is required when backup.enabled=true" .Values.postgres.host -}}
{{- end -}}
{{- if eq $src "pgdump" -}}
{{- $_ := required "storage.s3.bucket is required when verify.source=pgdump" .Values.storage.s3.bucket -}}
{{- end -}}
{{- if eq $src "walg" -}}
{{- if not (hasPrefix "s3://" (required "verify.walg.s3Prefix is required when verify.source=walg" .Values.verify.walg.s3Prefix)) -}}
{{- fail "verify.walg.s3Prefix must look like s3://bucket/path (same value as WALG_S3_PREFIX)" -}}
{{- end -}}
{{- end -}}
{{- $_ := required "postgres.database is required" .Values.postgres.database -}}
{{- end }}

{{/* Variables wal-g communes (le chemin S3 des backups et les options S3) */}}
{{- define "pgkube-guard.walgEnv" -}}
- name: WALG_S3_PREFIX
  value: {{ .Values.verify.walg.s3Prefix | quote }}
- name: AWS_S3_FORCE_PATH_STYLE
  value: {{ .Values.storage.s3.forcePathStyle | quote }}
{{- with .Values.storage.s3.endpoint }}
- name: AWS_ENDPOINT
  value: {{ . | quote }}
{{- end }}
{{- end }}
