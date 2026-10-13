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

{{- define "pgkube-guard.s3RestoreSecretName" -}}
{{- default (printf "%s-s3-restore" (include "pgkube-guard.fullname" .)) .Values.storage.s3.restoreCredentials.existingSecret }}
{{- end }}

{{- define "pgkube-guard.notificationsSecretName" -}}
{{- default (printf "%s-notifications" (include "pgkube-guard.fullname" .)) .Values.notifications.existingSecret }}
{{- end }}

{{/* Pod-level settings shared by both CronJobs */}}
{{- define "pgkube-guard.podSpecCommon" -}}
restartPolicy: Never
serviceAccountName: {{ include "pgkube-guard.serviceAccountName" . }}
automountServiceAccountToken: false
{{- with .Values.podSecurityContext }}
securityContext:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/* AWS credentials as env vars, from a Secret name and its key names */}}
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
