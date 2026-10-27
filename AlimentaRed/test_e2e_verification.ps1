# ==============================================================================
# SCRIPT DE VERIFICACIÓN AUTOMATIZADA E2E - ALIMENTARED API (100% ENDPOINTS)
# ==============================================================================

$baseUrl = "http://localhost:8080"
$global:passed = 0
$global:failed = 0
$global:results = @()

function Test-Endpoint {
    param(
        [string]$id,
        [string]$modulo,
        [string]$metodo,
        [string]$ruta,
        [int]$expectedStatus,
        [string]$token = $null,
        [object]$body = $null,
        [string]$descripcion = "",
        [bool]$isHtml = $false
    )

    $headers = @{}
    if (-not $isHtml) {
        $headers["Accept"] = "application/json"
    }
    if ($token) {
        $headers["Authorization"] = "Bearer $token"
    }

    $url = "$baseUrl$ruta"
    $status = 0
    $responseBody = $null

    try {
        $params = @{
            Uri = $url
            Method = $metodo
            Headers = $headers
            TimeoutSec = 10
        }
        if ($body) {
            $params["Body"] = ($body | ConvertTo-Json -Depth 5)
            $params["ContentType"] = "application/json; charset=utf-8"
        }

        $resp = Invoke-WebRequest @params -UseBasicParsing
        $status = $resp.StatusCode
        if (-not $isHtml) {
            $responseBody = $resp.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
        }
    }
    catch {
        if ($_.Exception.Response) {
            $status = [int]$_.Exception.Response.StatusCode
            try {
                $stream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream)
                $raw = $reader.ReadToEnd()
                $responseBody = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
            } catch {}
        } else {
            $status = 500
        }
    }

    $ok = ($status -eq $expectedStatus)
    if ($ok) {
        $global:passed++
        Write-Host " [PASS] $id ($modulo) - $metodo $ruta -> $status (Esperado: $expectedStatus)" -ForegroundColor Green
    } else {
        $global:failed++
        Write-Host " [FAIL] $id ($modulo) - $metodo $ruta -> $status (Esperado: $expectedStatus) - $descripcion" -ForegroundColor Red
        if ($responseBody) {
            Write-Host "        Detalle: $($responseBody.mensaje) ($($responseBody.codigo))" -ForegroundColor Yellow
        }
    }

    $global:results += [PSCustomObject]@{
        ID = $id
        Modulo = $modulo
        Metodo = $metodo
        Ruta = $ruta
        Esperado = $expectedStatus
        Obtenido = $status
        Resultado = if ($ok) { "PASS" } else { "FAIL" }
    }

    return $responseBody
}

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host " INICIANDO SUITE DE PRUEBAS AUTOMATIZADA PARA ALIMENTARED (100%)" -ForegroundColor Cyan
Write-Host " Servidor: $baseUrl" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

# --- 1. SISTEMA Y SALUD ---
Test-Endpoint "SYS-01" "Sistema" "Get" "/api/health" 200 -descripcion "Health UP"
Test-Endpoint "SYS-02" "Sistema" "Get" "/v3/api-docs" 200 -descripcion "OpenAPI JSON"
Test-Endpoint "SYS-03" "Sistema" "Get" "/swagger-ui/index.html" 200 -isHtml $true -descripcion "Swagger UI"

# --- 2. AUTENTICACIÓN Y ROLES ---
$authRec = Test-Endpoint "AUT-01" "Auth" "Post" "/api/auth/login" 200 -body @{
    correo = "receptora@pancompartido.org"
    contrasena = "Pass12345"
} -descripcion "Login Receptora 1"
$tokenRec = $authRec.token

$authRec2 = Test-Endpoint "AUT-02" "Auth" "Post" "/api/auth/login" 200 -body @{
    correo = "receptora@comedoresperanza.org"
    contrasena = "Pass12345"
} -descripcion "Login Receptora 2"
$tokenRec2 = $authRec2.token

$authDon = Test-Endpoint "AUT-03" "Auth" "Post" "/api/auth/login" 200 -body @{
    correo = "donante@saborcasero.com"
    contrasena = "Pass12345"
} -descripcion "Login Donante"
$tokenDon = $authDon.token

$authAdmin = Test-Endpoint "AUT-04" "Auth" "Post" "/api/auth/login" 200 -body @{
    correo = "admin@alimentared.com"
    contrasena = "Admin12345"
} -descripcion "Login Admin"
$tokenAdmin = $authAdmin.token

$authCoord = Test-Endpoint "AUT-05" "Auth" "Post" "/api/auth/login" 200 -body @{
    correo = "coordinador@alimentared.com"
    contrasena = "Coord12345"
} -descripcion "Login Coordinador"
$tokenCoord = $authCoord.token

# Prueba de cuenta suspendida por 3 strikes (RN08)
Test-Endpoint "AUT-06" "Auth" "Post" "/api/auth/login" 403 -body @{
    correo = "suspendido@abuelitospaz.org"
    contrasena = "Pass12345"
} -descripcion "RN08: Bloqueo de login por 3 strikes"

# Prueba de credenciales inválidas
Test-Endpoint "AUT-07" "Auth" "Post" "/api/auth/login" 401 -body @{
    correo = "donante@saborcasero.com"
    contrasena = "ClaveErronea123"
} -descripcion "Login rechazado con 401"

# --- 3. PERFIL Y USUARIOS ---
Test-Endpoint "USR-01" "Usuarios" "Get" "/api/usuarios/me" 200 -token $tokenRec -descripcion "Perfil Receptora"
Test-Endpoint "USR-02" "Usuarios" "Get" "/api/usuarios/me" 200 -token $tokenDon -descripcion "Perfil Donante"

# --- 4. CATEGORÍAS (CATÁLOGO) ---
$categorias = Test-Endpoint "CAT-01" "Categorías" "Get" "/api/categorias" 200 -token $tokenRec -descripcion "Listar categorías"

# --- 5. LOTES DE ALIMENTOS ---
$lotes = Test-Endpoint "LOT-01" "Lotes" "Get" "/api/lotes" 200 -token $tokenRec -descripcion "Listar lotes disponibles"
$primerLoteId = $lotes.contenido[0].id
Test-Endpoint "LOT-02" "Lotes" "Get" "/api/lotes/$primerLoteId" 200 -token $tokenRec -descripcion "Detalle de lote"
Test-Endpoint "LOT-03" "Lotes" "Get" "/api/lotes/mis-lotes" 200 -token $tokenDon -descripcion "Mis lotes (Donante)"

# Publicar un lote de prueba válido (RF03)
$fechaCad = (Get-Date).AddHours(8).ToString("yyyy-MM-ddTHH:mm:ss")
$nuevoLote = Test-Endpoint "LOT-04" "Lotes" "Post" "/api/lotes" 201 -token $tokenDon -body @{
    nombre = "Fruta de Temporada Suite Test"
    descripcion = "Prueba automatizada de publicación de lote fresco"
    categoriaId = 1
    cantidad = 50.000
    unidadMinima = 5.000
    multiplo = 5.000
    estadoAlimento = "FRESCO"
    fechaCaducidad = $fechaCad
    ubicacion = "Almacén Central, Muelle 3"
    instruccionesRecogida = "Preguntar por bodega de despachos"
    contacto = "3109998877"
} -descripcion "RF03: Publicar lote"
$loteCreadoId = $nuevoLote.id
if (-not $loteCreadoId) { $loteCreadoId = $primerLoteId }

# Auditoría del lote (RN04)
Test-Endpoint "LOT-05" "Lotes" "Get" "/api/lotes/$loteCreadoId/historial" 200 -token $tokenDon -descripcion "RN04: Auditoría de estados del lote"

# --- 6. SOLICITUDES DE DONACIÓN (RECEPTORA) ---
# Conteo de activas inicial
Test-Endpoint "SOL-01" "Solicitudes" "Get" "/api/solicitudes/activas/conteo" 200 -token $tokenRec -descripcion "RN07: Conteo de solicitudes activas"

# Crear solicitud válida (RF05)
$solicitudCreada = Test-Endpoint "SOL-02" "Solicitudes" "Post" "/api/solicitudes" 201 -token $tokenRec -body @{
    loteId = $loteCreadoId
    cantidadSolicitada = 10.000
} -descripcion "RF05: Crear solicitud de donación"
$solicitudId = $solicitudCreada.id

# Validación RN02: Cantidad mayor a disponible con Receptora 2 sobre Lote 2
Test-Endpoint "SOL-03" "Solicitudes" "Post" "/api/solicitudes" 422 -token $tokenRec2 -body @{
    loteId = 2
    cantidadSolicitada = 500.000
} -descripcion "RN02: Rechazo 422 por stock insuficiente"

# Validación RN05: Inferior a unidad mínima o no múltiplo con Receptora 2 sobre Lote 2 (unidadMinima=20, multiplo=10)
Test-Endpoint "SOL-04" "Solicitudes" "Post" "/api/solicitudes" 422 -token $tokenRec2 -body @{
    loteId = 2
    cantidadSolicitada = 5.000
} -descripcion "RN05: Rechazo 422 por unidad mínima"

# Consultar mis solicitudes
Test-Endpoint "SOL-05" "Solicitudes" "Get" "/api/solicitudes/mis-solicitudes" 200 -token $tokenRec -descripcion "Mis solicitudes (Receptora)"

if ($solicitudId) {
    Test-Endpoint "SOL-06" "Solicitudes" "Get" "/api/solicitudes/$solicitudId" 200 -token $tokenRec -descripcion "Detalle de solicitud"
    Test-Endpoint "SOL-07" "Solicitudes" "Get" "/api/solicitudes/lote/$loteCreadoId" 200 -token $tokenDon -descripcion "Solicitudes recibidas por lote (Donante)"
    Test-Endpoint "SOL-08" "Solicitudes" "Get" "/api/solicitudes/$solicitudId/historial" 200 -token $tokenRec -descripcion "RN04: Historial de la solicitud"

    # Resolver solicitud: Aprobar por el donante (RF06)
    $solResuelta = Test-Endpoint "SOL-09" "Solicitudes" "Patch" "/api/solicitudes/$solicitudId/resolver" 200 -token $tokenDon -body @{
        aprobada = $true
        motivo = "Aprobado por suite automatizada de pruebas"
    } -descripcion "RF06: Donante aprueba solicitud y crea asignación"
}

# --- 7. ENTREGAS Y ASIGNACIONES ---
$asignaciones = Test-Endpoint "ENT-01" "Entregas" "Get" "/api/entregas/asignaciones" 200 -token $tokenDon -descripcion "Listar asignaciones"
$asigId = $asignaciones.contenido[0].id

if ($asigId) {
    Test-Endpoint "ENT-02" "Entregas" "Get" "/api/entregas/asignaciones/$asigId" 200 -token $tokenRec -descripcion "Detalle asignación con instrucciones"

    # Confirmar entrega completa a tiempo (RF07)
    Test-Endpoint "ENT-03" "Entregas" "Patch" "/api/entregas/$asigId/confirmar" 200 -token $tokenDon -body @{
        cantidadRetirada = 10.000
        observaciones = "Retiro verificado en portería"
    } -descripcion "RF07: Confirmación de entrega exitosa"

    # Consultar retiros registrados para esa asignación
    Test-Endpoint "ENT-04" "Entregas" "Get" "/api/entregas/asignaciones/$asigId/retiros" 200 -token $tokenDon -descripcion "Retiros registrados de asignación"
}

# --- 8. INCIDENCIAS DE INOCUIDAD (RF08) ---
$incidencia = Test-Endpoint "INC-01" "Incidencias" "Post" "/api/incidencias" 201 -token $tokenRec -body @{
    loteId = $loteCreadoId
    detalles = "Reporte de prueba: verificación rigurosa de cadena de frío y empaque"
} -descripcion "RF08: Reporte de anomalía e inocuidad"
$incId = $incidencia.id

Test-Endpoint "INC-02" "Incidencias" "Get" "/api/incidencias" 200 -token $tokenCoord -descripcion "Listar incidencias (Coordinador)"
Test-Endpoint "INC-03" "Incidencias" "Get" "/api/incidencias/lote/$loteCreadoId" 200 -token $tokenDon -descripcion "Incidencias por lote"

if ($incId) {
    Test-Endpoint "INC-04" "Incidencias" "Patch" "/api/incidencias/$incId/resolver" 200 -token $tokenCoord -body @{
        reactivarLote = $true
        resolucion = "Incidencia solventada tras inspección física detallada"
    } -descripcion "Resolver y reactivar incidencia"
}

# --- 9. ORGANIZACIONES Y STRIKES ---
Test-Endpoint "ORG-01" "Organizaciones" "Get" "/api/organizaciones" 200 -token $tokenAdmin -descripcion "Listar organizaciones (Admin)"
Test-Endpoint "ORG-02" "Organizaciones" "Get" "/api/organizaciones/3" 200 -token $tokenRec -descripcion "Detalle organización Pan Compartido"
Test-Endpoint "ORG-03" "Organizaciones" "Get" "/api/organizaciones/5/strikes" 200 -token $tokenAdmin -descripcion "Consultar strikes de org suspendida"

# --- 10. REPORTES DE IMPACTO (RF09) ---
Test-Endpoint "REP-01" "Reportes" "Get" "/api/reportes/impacto" 200 -token $tokenCoord -descripcion "RF09: Indicadores globales de impacto"
Test-Endpoint "REP-02" "Reportes" "Get" "/api/reportes/historial" 200 -token $tokenDon -descripcion "Historial general de donaciones"

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host " RESUMEN FINAL DE LA SUITE DE PRUEBAS" -ForegroundColor Cyan
Write-Host " Pruebas Exitosas: $global:passed" -ForegroundColor Green
Write-Host " Pruebas Fallidas: $global:failed" -ForegroundColor $(if ($global:failed -eq 0) { "Green" } else { "Red" })
$total = $global:passed + $global:failed
$pct = [Math]::Round(($global:passed / $total) * 100, 1)
Write-Host " Porcentaje de Cobertura Funcional: $pct %" -ForegroundColor $(if ($pct -eq 100) { "Green" } else { "Yellow" })
Write-Host "==================================================================" -ForegroundColor Cyan
