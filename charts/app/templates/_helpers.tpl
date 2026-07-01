{{/*
Common labels for a service.
Call with a dict: { "root": $, "name": <serviceName>, "image": <imageRef> }
The version label is derived from the image tag (these apps are not semver-versioned).
*/}}
{{- define "app.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .root.Chart.Name .root.Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
{{- $version := include "app.version" .image }}
{{- if $version }}
app.kubernetes.io/version: {{ $version | quote }}
{{- end }}
{{- end -}}

{{/*
Derive a version label value from an image reference: the tag (after the last
colon) or, for digest references, the hex digest. Returns "" when neither is
present. Guards against the registry-port colon (e.g. registry:5000/repo).
*/}}
{{- define "app.version" -}}
{{- $ref := . | toString -}}
{{- $version := "" -}}
{{- if contains "@" $ref -}}
{{- $version = $ref | splitList "@" | last | splitList ":" | last -}}
{{- else -}}
{{- $lastSegment := $ref | splitList "/" | last -}}
{{- if contains ":" $lastSegment -}}
{{- $version = $lastSegment | splitList ":" | last -}}
{{- end -}}
{{- end -}}
{{- $version | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Selector labels for a service (stable across upgrades).
Call with a dict: { "root": $, "name": <serviceName> }
*/}}
{{- define "app.selectorLabels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
{{- end -}}

{{/*
Fully qualified name for a service: <release>-<serviceName>, truncated to 63 chars.
Call with a dict: { "root": $, "name": <serviceName> }
*/}}
{{- define "app.fullname" -}}
{{- printf "%s-%s" .root.Release.Name .name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
