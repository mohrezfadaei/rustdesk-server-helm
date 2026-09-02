{{/*
Chart name, optionally overridden by nameOverride.
*/}}
{{- define "rustdesk-server.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Fully qualified release name.
*/}}
{{- define "rustdesk-server.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "rustdesk-server.hbbs.fullname" -}}
{{- printf "%s-hbbs" (include "rustdesk-server.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "rustdesk-server.hbbr.fullname" -}}
{{- printf "%s-hbbr" (include "rustdesk-server.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "rustdesk-server.namespace" -}}
{{- default .Release.Namespace .Values.namespaceOverride -}}
{{- end -}}

{{- define "rustdesk-server.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Render a value that may contain template directives.
{{ include "rustdesk-server.tplvalues" (dict "value" .Values.foo "context" $) }}
*/}}
{{- define "rustdesk-server.tplvalues" -}}
{{- $value := typeIs "string" .value | ternary .value (toYaml .value) -}}
{{- tpl $value .context -}}
{{- end -}}

{{/*
Standard labels. Pass a component to add app.kubernetes.io/component.
{{ include "rustdesk-server.labels" (dict "component" "hbbs" "context" $) }}
*/}}
{{- define "rustdesk-server.labels" -}}
app.kubernetes.io/name: {{ include "rustdesk-server.name" .context }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
app.kubernetes.io/managed-by: {{ .context.Release.Service }}
app.kubernetes.io/part-of: rustdesk-server
helm.sh/chart: {{ include "rustdesk-server.chart" .context }}
{{- with .context.Chart.AppVersion }}
app.kubernetes.io/version: {{ . | quote }}
{{- end }}
{{- with .component }}
app.kubernetes.io/component: {{ . }}
{{- end }}
{{- with .context.Values.commonLabels }}
{{ include "rustdesk-server.tplvalues" (dict "value" . "context" $.context) }}
{{- end }}
{{- end -}}

{{/*
Labels used in immutable selectors, so custom labels are deliberately excluded.
*/}}
{{- define "rustdesk-server.selectorLabels" -}}
app.kubernetes.io/name: {{ include "rustdesk-server.name" .context }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{/*
Image reference, honouring global.imageRegistry and image.digest.
*/}}
{{- define "rustdesk-server.image" -}}
{{- $registry := .Values.image.registry -}}
{{- with .Values.global }}{{- $registry = .imageRegistry | default $registry }}{{- end -}}
{{- $repository := .Values.image.repository -}}
{{- if .Values.image.digest -}}
{{- $tag := .Values.image.digest | toString -}}
{{- if $registry }}{{ printf "%s/%s@%s" $registry $repository $tag }}{{ else }}{{ printf "%s@%s" $repository $tag }}{{ end -}}
{{- else -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion | toString -}}
{{- if $registry }}{{ printf "%s/%s:%s" $registry $repository $tag }}{{ else }}{{ printf "%s:%s" $repository $tag }}{{ end -}}
{{- end -}}
{{- end -}}

{{/*
Merged image pull secrets from image.pullSecrets and global.imagePullSecrets.
*/}}
{{- define "rustdesk-server.imagePullSecrets" -}}
{{- $secrets := .Values.image.pullSecrets -}}
{{- with .Values.global }}{{- $secrets = concat (.imagePullSecrets | default list) $secrets }}{{- end -}}
{{- with $secrets }}
imagePullSecrets:
{{- range . | uniq }}
  - name: {{ . }}
{{- end }}
{{- end }}
{{- end -}}

{{- define "rustdesk-server.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "rustdesk-server.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Name of the Secret holding the key pair, whether existing or chart-managed.
*/}}
{{- define "rustdesk-server.secretName" -}}
{{- if .Values.auth.existingSecret -}}
{{- tpl .Values.auth.existingSecret . -}}
{{- else -}}
{{- printf "%s-keys" (include "rustdesk-server.fullname" .) -}}
{{- end -}}
{{- end -}}

{{/*
True when the chart should create the key pair Secret from inline values.
*/}}
{{- define "rustdesk-server.createKeySecret" -}}
{{- if and (not .Values.auth.existingSecret) .Values.auth.publicKey .Values.auth.privateKey -}}
true
{{- end -}}
{{- end -}}

{{/*
True when a key pair is available to mount, from either source.
*/}}
{{- define "rustdesk-server.hasKeys" -}}
{{- if or .Values.auth.existingSecret (include "rustdesk-server.createKeySecret" .) -}}
true
{{- end -}}
{{- end -}}

{{/*
storageClassName line for a PVC, or nothing to use the cluster default.
{{ include "rustdesk-server.storageClass" (dict "persistence" .Values.hbbs.persistence "context" $) }}
*/}}
{{- define "rustdesk-server.storageClass" -}}
{{- $class := .persistence.storageClass -}}
{{- with .context.Values.global }}{{- $class = $class | default .defaultStorageClass }}{{- end -}}
{{- if $class -}}
{{- if eq "-" $class -}}
storageClassName: ""
{{- else -}}
storageClassName: {{ $class }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Container resources, from an explicit block or a named preset.
Presets are for basic testing and are not meant for production sizing.
{{ include "rustdesk-server.resources" (dict "component" .Values.hbbs "context" $) }}
*/}}
{{- define "rustdesk-server.resources" -}}
{{- if .component.resources -}}
{{- toYaml .component.resources -}}
{{- else if and .component.resourcesPreset (ne .component.resourcesPreset "none") -}}
{{- $presets := dict
  "nano" (dict "requests" (dict "cpu" "100m" "memory" "128Mi" "ephemeral-storage" "50Mi") "limits" (dict "cpu" "150m" "memory" "192Mi" "ephemeral-storage" "2Gi"))
  "micro" (dict "requests" (dict "cpu" "250m" "memory" "256Mi" "ephemeral-storage" "50Mi") "limits" (dict "cpu" "375m" "memory" "384Mi" "ephemeral-storage" "2Gi"))
  "small" (dict "requests" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "50Mi") "limits" (dict "cpu" "750m" "memory" "768Mi" "ephemeral-storage" "2Gi"))
  "medium" (dict "requests" (dict "cpu" "500m" "memory" "1024Mi" "ephemeral-storage" "50Mi") "limits" (dict "cpu" "750m" "memory" "1536Mi" "ephemeral-storage" "2Gi"))
  "large" (dict "requests" (dict "cpu" "1.0" "memory" "2048Mi" "ephemeral-storage" "50Mi") "limits" (dict "cpu" "1.5" "memory" "3072Mi" "ephemeral-storage" "2Gi"))
  "xlarge" (dict "requests" (dict "cpu" "1.0" "memory" "3072Mi" "ephemeral-storage" "50Mi") "limits" (dict "cpu" "3.0" "memory" "6144Mi" "ephemeral-storage" "2Gi"))
  "2xlarge" (dict "requests" (dict "cpu" "1.0" "memory" "3072Mi" "ephemeral-storage" "50Mi") "limits" (dict "cpu" "6.0" "memory" "12288Mi" "ephemeral-storage" "2Gi"))
-}}
{{- if hasKey $presets .component.resourcesPreset -}}
{{- index $presets .component.resourcesPreset | toYaml -}}
{{- else -}}
{{- fail (printf "resourcesPreset %q is invalid. Allowed values are none,%s" .component.resourcesPreset (join "," (keys $presets))) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Affinity for a component, either the explicit block or the presets.
{{ include "rustdesk-server.affinity" (dict "component" "hbbs" "values" .Values.hbbs "context" $) }}
*/}}
{{- define "rustdesk-server.affinity" -}}
{{- if .values.affinity -}}
{{- include "rustdesk-server.tplvalues" (dict "value" .values.affinity "context" .context) -}}
{{- else -}}
{{- $selector := include "rustdesk-server.selectorLabels" (dict "component" .component "context" .context) | fromYaml -}}
{{- with .values.nodeAffinityPreset.type }}
nodeAffinity:
  {{- if eq . "soft" }}
  preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 1
      preference:
        matchExpressions:
          - key: {{ $.values.nodeAffinityPreset.key }}
            operator: In
            values:
              {{- range $.values.nodeAffinityPreset.values }}
              - {{ . | quote }}
              {{- end }}
  {{- else }}
  requiredDuringSchedulingIgnoredDuringExecution:
    nodeSelectorTerms:
      - matchExpressions:
          - key: {{ $.values.nodeAffinityPreset.key }}
            operator: In
            values:
              {{- range $.values.nodeAffinityPreset.values }}
              - {{ . | quote }}
              {{- end }}
  {{- end }}
{{- end }}
{{- with .values.podAffinityPreset }}
podAffinity:
  {{- include "rustdesk-server.affinityTerm" (dict "preset" . "selector" $selector "context" $.context) | trim | nindent 2 }}
{{- end }}
{{- with .values.podAntiAffinityPreset }}
podAntiAffinity:
  {{- include "rustdesk-server.affinityTerm" (dict "preset" . "selector" $selector "context" $.context) | trim | nindent 2 }}
{{- end }}
{{- end -}}
{{- end -}}

{{- define "rustdesk-server.affinityTerm" -}}
{{- if eq .preset "soft" }}
preferredDuringSchedulingIgnoredDuringExecution:
  - weight: 1
    podAffinityTerm:
      labelSelector:
        matchLabels: {{- toYaml .selector | nindent 10 }}
      namespaces:
        - {{ include "rustdesk-server.namespace" .context }}
      topologyKey: kubernetes.io/hostname
{{- else }}
requiredDuringSchedulingIgnoredDuringExecution:
  - labelSelector:
      matchLabels: {{- toYaml .selector | nindent 8 }}
    namespaces:
      - {{ include "rustdesk-server.namespace" .context }}
    topologyKey: kubernetes.io/hostname
{{- end }}
{{- end -}}

{{/*
Render a securityContext, dropping the fields OpenShift's restricted-v2 SCC assigns itself.
{{ include "rustdesk-server.securityContext" (dict "secContext" .Values.hbbs.containerSecurityContext "context" $) }}
*/}}
{{- define "rustdesk-server.securityContext" -}}
{{- $context := omit .secContext "enabled" -}}
{{- $openshift := .context.Capabilities.APIVersions.Has "security.openshift.io/v1" -}}
{{- $adapt := (((.context.Values.global).compatibility).openshift).adaptSecurityContext | default "auto" -}}
{{- if or (eq $adapt "force") (and (eq $adapt "auto") $openshift) -}}
{{- $context = omit $context "runAsUser" "runAsGroup" "fsGroup" -}}
{{- end -}}
{{- if not .secContext.seLinuxOptions -}}
{{- $context = omit $context "seLinuxOptions" -}}
{{- end -}}
{{- if .secContext.privileged -}}
{{- $context = omit $context "capabilities" -}}
{{- end -}}
{{- toYaml $context -}}
{{- end -}}

{{/*
Relay addresses passed to hbbs with -r, empty when clients should derive them.
*/}}
{{- define "rustdesk-server.relayServers" -}}
{{- $servers := list -}}
{{- range .Values.relayServers -}}
{{- $servers = append $servers (tpl (toString .) $) -}}
{{- end -}}
{{- join "," $servers -}}
{{- end -}}
