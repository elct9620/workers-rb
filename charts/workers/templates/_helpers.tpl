{{/*
The names and labels every object in this release carries, and the two
decisions that are read from more than one template: which claim holds the
shared directory, and where the Hosts reach the databases.
*/}}

{{- define "workers.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "workers.fullname" -}}
{{- if contains .Chart.Name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "workers.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "workers.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels are fixed for the life of a Deployment, so the component that
tells a Host apart from the database server is set here from the start rather
than added once both exist.
*/}}
{{- define "workers.selectorLabels" -}}
app.kubernetes.io/name: {{ include "workers.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: host
{{- end -}}

{{- define "workers.image" -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default .Chart.AppVersion) -}}
{{- end -}}

{{/*
The claim every Host mounts at /app. An operator supplies a claim or a class
that can provision one; neither is defaulted, because a shared directory only
one Host can read produces a cluster that disagrees about which Tenants exist
without any of them reporting an error.
*/}}
{{- define "workers.sharedClaim" -}}
{{- if .Values.sharedDirectory.existingClaim -}}
{{- .Values.sharedDirectory.existingClaim -}}
{{- else if .Values.sharedDirectory.storageClass -}}
{{- printf "%s-app" (include "workers.fullname" .) -}}
{{- else -}}
{{- fail "sharedDirectory needs either existingClaim or storageClass: every Host reads the same directory, and a ReadWriteMany volume is what lets them. Set sharedDirectory.existingClaim to a claim you already have, or sharedDirectory.storageClass to a class that can provision one." -}}
{{- end -}}
{{- end -}}

{{- define "workers.db.fullname" -}}
{{- printf "%s-db" (include "workers.fullname" .) -}}
{{- end -}}

{{/*
Where a Host runs statements, and where it has a database made that a Manifest
declared but nothing created yet. The service this resolves to is headless, so
the name answers on the admin port too without that port being published.
*/}}
{{- define "workers.db.url" -}}
{{- if .Values.databases.deploy -}}
{{- printf "http://%s:8080" (include "workers.db.fullname" .) -}}
{{- else if .Values.databases.url -}}
{{- .Values.databases.url -}}
{{- else -}}
{{- fail "databases.url is needed when databases.deploy is false: the Hosts have to name a server holding the Tenants' databases, and this chart is not installing one." -}}
{{- end -}}
{{- end -}}

{{- define "workers.db.adminUrl" -}}
{{- if .Values.databases.deploy -}}
{{- printf "http://%s:8081" (include "workers.db.fullname" .) -}}
{{- else if .Values.databases.adminUrl -}}
{{- .Values.databases.adminUrl -}}
{{- else -}}
{{- fail "databases.adminUrl is needed when databases.deploy is false: a Host creates a declared database the first time a Tenant reaches for one, which the serving port does not do." -}}
{{- end -}}
{{- end -}}
