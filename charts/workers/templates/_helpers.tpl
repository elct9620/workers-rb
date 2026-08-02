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
The claim every Host mounts at /app, read-only. The operator supplies it and
this chart never creates one: how the volume is backed and how Tenants are
written into it are one decision, and a claim made here would carry no way to
publish through. It is not defaulted either, because a directory only one Host
can read produces a cluster that disagrees about which Tenants exist without
any of them reporting an error.
*/}}
{{- define "workers.sharedClaim" -}}
{{- if .Values.sharedDirectory.existingClaim -}}
{{- .Values.sharedDirectory.existingClaim -}}
{{- else -}}
{{- fail "sharedDirectory.existingClaim is needed: every Host reads the same directory, so name a claim every Node can mount for reading and whatever publishes Tenants can write to." -}}
{{- end -}}
{{- end -}}

{{- define "workers.db.fullname" -}}
{{- printf "%s-db" (include "workers.fullname" .) -}}
{{- end -}}

{{- define "workers.db.selectorLabels" -}}
app.kubernetes.io/name: {{ include "workers.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: database
{{- end -}}

{{/*
The database server carries no `version` label: what it runs is the image an
operator named, which the chart's own appVersion does not speak for.
*/}}
{{- define "workers.db.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "workers.db.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
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
