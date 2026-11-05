<?php
declare(strict_types=1);

session_set_cookie_params([
    'httponly' => true,
    'samesite' => 'Strict',
    'secure' => !empty($_SERVER['HTTPS'])
        || ($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https',
]);
session_start();

header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');
header("Content-Security-Policy: frame-ancestors 'none'");

$actionsDir = '/config/www/actions';
$versionsFile = '/config/www/actions/settings/versions.json';
$hostIpFile = '/config/www/actions/settings/host-ip.txt';

$zigbeeContainerName = 'zigbee2mqtt';
$nodeRedContainerName = 'node-red-node-red-1';
$homeAssistantContainerName = 'homeassistant';

$mosquittoCredentialsFile =
    '/config/www/actions/settings/current-credentials.txt';

$systemUpdateEnabled = false;

// If versions.json is older than this, the handler is probably not running.
$handlerStaleSeconds = 7200;

$allowedActions = [
    'System' => ['Reboot', 'Update'],
    'Zigbee2MQTT' => ['Start', 'Stop', 'Restart', 'Update'],
    'Node-RED' => ['Start', 'Stop', 'Restart', 'Update'],
    'Home Assistant' => ['Start', 'Stop', 'Restart', 'Update'],
];

$serviceLinks = [
    'Zigbee2MQTT' => [
        'url' => '/zigbee/',
        'label' => 'Open Zigbee2MQTT',
    ],
    'Node-RED' => [
        'url' => '/node-red/',
        'label' => 'Open Node-RED',
    ],
    'Home Assistant' => [
        'url' => '/',
        'label' => 'Open Home Assistant',
    ],
];

if (!isset($_SESSION['csrf'])) {
    $_SESSION['csrf'] = bin2hex(random_bytes(32));
}

function escape(string $value): string
{
    return htmlspecialchars(
        $value,
        ENT_QUOTES | ENT_SUBSTITUTE,
        'UTF-8'
    );
}

function postValue(string $key): string
{
    $value = $_POST[$key] ?? '';

    return is_string($value) ? $value : '';
}

/**
 * Returns [css class, label] for the update line of a service.
 * Shows "Status unknown" instead of "Up to date" when a version
 * could not be determined.
 *
 * The handler's "update_available" flag is not trusted on its own:
 * the installed and latest versions are compared here as well, so a
 * wrong or missing flag can no longer hide a real update.
 */
function updateStatus(
    string $installed,
    string $latest,
    bool $available
): array {
    if ($installed === 'Unknown' || $latest === 'Unknown') {
        return ['status-unknown', 'Status unknown'];
    }

    // Strip a leading "v" (common in Node-RED / Zigbee2MQTT tags).
    $normalize = static fn (string $v): string => ltrim(trim($v), 'vV');

    $available = $available || version_compare(
        $normalize($installed),
        $normalize($latest),
        '<'
    );

    return $available
        ? ['update-available', 'Update available']
        : ['up-to-date', 'Up to date'];
}

function publishCommand(
    string $directory,
    string $name,
    string $contents
): bool {
    if (!is_dir($directory) || !is_writable($directory)) {
        return false;
    }

    $temporary = $directory . '/.pending-' . bin2hex(random_bytes(8));
    $destination = $directory . '/' . $name;

    $oldUmask = umask(0077);

    $written = @file_put_contents(
        $temporary,
        $contents,
        LOCK_EX
    );

    umask($oldUmask);

    if ($written === false) {
        @unlink($temporary);
        return false;
    }

    if (!@rename($temporary, $destination)) {
        @unlink($temporary);
        return false;
    }

    return true;
}

$message = '';
$messageType = 'success';

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'POST') {
    $category = postValue('category');
    $button = postValue('button');

    if (!hash_equals($_SESSION['csrf'], postValue('csrf'))) {
        $message = 'Session check failed. Refresh the page and try again.';
        $messageType = 'error';

    } elseif ($category === 'Mosquitto' && $button === 'AddUser') {
        $username = trim(postValue('username'));
        $password = postValue('password');
        $confirmation = postValue('confirm_password');

        if (
            $username === '' ||
            $password === '' ||
            $confirmation === ''
        ) {
            $message = 'Please fill in all Mosquitto fields.';
            $messageType = 'error';
        } elseif ($password !== $confirmation) {
            $message = 'The passwords do not match.';
            $messageType = 'error';
        } elseif (
            !preg_match('/^[A-Za-z0-9._@-]{1,64}$/', $username) ||
            preg_match('/[\r\n\x00]/', $password)
        ) {
            $message = 'Username: 1–64 letters, numbers, dots, underscores, '
                . '@ or hyphens. The password cannot contain line breaks.';
            $messageType = 'error';
        } else {
            $content = $username . "\n" . $password . "\n";

            if (publishCommand(
                $actionsDir,
                'Mosquitto-AddUser',
                $content
            )) {
                $message = 'Mosquitto credential replacement queued. '
                    . 'The current credentials will update after '
                    . 'the handler completes the request.';
            } else {
                $message = 'Failed to create Mosquitto request. '
                    . 'Check the commands directory and permissions.';
                $messageType = 'error';
            }
        }

    } elseif (
        $category === 'Node-RED' &&
        $button === 'SetCredentials'
    ) {
        $username = trim(postValue('username'));
        $password = postValue('password');
        $confirmation = postValue('confirm_password');

        if (
            $username === '' ||
            $password === '' ||
            $confirmation === ''
        ) {
            $message = 'Please fill in all Node-RED login fields.';
            $messageType = 'error';
        } elseif ($password !== $confirmation) {
            $message = 'The Node-RED passwords do not match.';
            $messageType = 'error';
        } elseif (
            !preg_match('/^[A-Za-z0-9_.-]{1,64}$/', $username) ||
            preg_match('/[\r\n\x00]/', $password)
        ) {
            $message = 'Unsupported Node-RED username or password.';
            $messageType = 'error';
        } else {
            $content = $username . "\n" . $password . "\n";

            if (publishCommand(
                $actionsDir,
                'Node-RED-SetCredentials',
                $content
            )) {
                $message = 'Node-RED login change queued.';
            } else {
                $message = 'Failed to queue Node-RED login change.';
                $messageType = 'error';
            }
        }

    } elseif (
        $category === 'Zigbee2MQTT' &&
        $button === 'SetToken'
    ) {
        $token = trim(postValue('token'));
        $confirmation = trim(postValue('confirm_token'));

        if ($token === '' || $confirmation === '') {
            $message = 'Please fill in both Zigbee2MQTT token fields.';
            $messageType = 'error';
        } elseif ($token !== $confirmation) {
            $message = 'The Zigbee2MQTT tokens do not match.';
            $messageType = 'error';
        } elseif (
            !preg_match('/^[A-Za-z0-9_.-]{16,128}$/', $token)
        ) {
            $message = 'Use 16–128 letters, numbers, dots, underscores, '
                . 'or hyphens.';
            $messageType = 'error';
        } else {
            if (publishCommand(
                $actionsDir,
                'Zigbee2MQTT-SetToken',
                $token . "\n"
            )) {
                $message = 'Zigbee2MQTT token change queued.';
            } else {
                $message = 'Failed to queue Zigbee2MQTT token change.';
                $messageType = 'error';
            }
        }

    } elseif (
        $category === 'Home Assistant' &&
        $button === 'SetPassword'
    ) {
        $username = trim(postValue('username'));
        $password = postValue('password');
        $confirmation = postValue('confirm_password');

        if (
            $username === '' ||
            $password === '' ||
            $confirmation === ''
        ) {
            $message = 'Please fill in all Home Assistant fields.';
            $messageType = 'error';
        } elseif ($password !== $confirmation) {
            $message = 'The Home Assistant passwords do not match.';
            $messageType = 'error';
        } elseif (
            !preg_match('/^[A-Za-z0-9._@-]{1,64}$/', $username) ||
            preg_match('/[\r\n\x00]/', $password)
        ) {
            $message = 'Unsupported Home Assistant username or password.';
            $messageType = 'error';
        } else {
            $content = $username . "\n" . $password . "\n";

            if (publishCommand(
                $actionsDir,
                'HomeAssistant-SetPassword',
                $content
            )) {
                $message = 'Home Assistant password change queued.';
            } else {
                $message = 'Failed to queue Home Assistant password change.';
                $messageType = 'error';
            }
        }

    } elseif (
        isset($allowedActions[$category]) &&
        in_array($button, $allowedActions[$category], true)
    ) {
        if (
            $category === 'System' &&
            $button === 'Update' &&
            !$systemUpdateEnabled
        ) {
            $message = 'Host system updates are not configured yet.';
            $messageType = 'error';
        } else {
            $name = $category . '-' . $button;

            if (publishCommand($actionsDir, $name, '')) {
                $message = 'Action queued: ' . $name;
                $_SESSION['refresh'] = true;
            } else {
                $message = 'Failed to create: ' . $name
                    . '. Check the commands directory and permissions.';
                $messageType = 'error';
            }
        }
    } else {
        $message = 'Invalid action.';
        $messageType = 'error';
    }

    $_SESSION['flash'] = [$message, $messageType];

    header('Location: /admin/', true, 303);
    exit;
}

if (isset($_SESSION['flash'])) {
    [$message, $messageType] = $_SESSION['flash'];
    unset($_SESSION['flash']);
}

// After a queued action the page reloads itself for about a minute,
// so the new version numbers show up once the handler is done.
$refresh = !empty($_SESSION['refresh']);
unset($_SESSION['refresh']);

$versions = [
    'zigbee2mqtt' => [
        'installed' => 'Unknown',
        'latest' => 'Unknown',
        'update_available' => false,
    ],
    'node-red' => [
        'installed' => 'Unknown',
        'latest' => 'Unknown',
        'update_available' => false,
    ],
    'home-assistant' => [
        'installed' => 'Unknown',
        'latest' => 'Unknown',
        'update_available' => false,
    ],
];

$handlerStale = false;

if (is_readable($versionsFile)) {
    $versionsText = @file_get_contents($versionsFile);

    if (is_string($versionsText) && $versionsText !== '') {
        $decoded = json_decode($versionsText, true);

        if (is_array($decoded)) {
            foreach (['zigbee2mqtt', 'node-red', 'home-assistant'] as $service) {
                if (
                    isset($decoded[$service]) &&
                    is_array($decoded[$service])
                ) {
                    $versions[$service] = array_merge(
                        $versions[$service],
                        $decoded[$service]
                    );
                }
            }

            if (isset($decoded['updated_at']) && is_string($decoded['updated_at'])) {
                $updatedAt = strtotime($decoded['updated_at']);

                if (
                    $updatedAt !== false &&
                    (time() - $updatedAt) > $handlerStaleSeconds
                ) {
                    $handlerStale = true;
                }
            }
        }
    }
}

$zigbeeInstalled = (string) $versions['zigbee2mqtt']['installed'];
$zigbeeLatest = (string) $versions['zigbee2mqtt']['latest'];
$zigbeeUpdateAvailable = filter_var(
    $versions['zigbee2mqtt']['update_available'],
    FILTER_VALIDATE_BOOLEAN
);

$nodeRedInstalled = (string) $versions['node-red']['installed'];
$nodeRedLatest = (string) $versions['node-red']['latest'];
$nodeRedUpdateAvailable = filter_var(
    $versions['node-red']['update_available'],
    FILTER_VALIDATE_BOOLEAN
);

$homeAssistantInstalled = (string) $versions['home-assistant']['installed'];
$homeAssistantLatest = (string) $versions['home-assistant']['latest'];
$homeAssistantUpdateAvailable = filter_var(
    $versions['home-assistant']['update_available'],
    FILTER_VALIDATE_BOOLEAN
);

$zigbeeStatus = updateStatus(
    $zigbeeInstalled,
    $zigbeeLatest,
    $zigbeeUpdateAvailable
);
$nodeRedStatus = updateStatus(
    $nodeRedInstalled,
    $nodeRedLatest,
    $nodeRedUpdateAvailable
);
$homeAssistantStatus = updateStatus(
    $homeAssistantInstalled,
    $homeAssistantLatest,
    $homeAssistantUpdateAvailable
);

$hostIp = '';
$hostLastOctet = '';

if (is_readable($hostIpFile)) {
    $hostIp = trim(
        (string) @file_get_contents($hostIpFile)
    );

    if (
        preg_match(
            '/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/',
            $hostIp,
            $ipMatches
        )
    ) {
        $hostLastOctet = $ipMatches[4];
    }
}

$secureMqttPortLabel = $hostLastOctet !== ''
    ? $hostLastOctet . '00'
    : 'Unknown';

$unsecureMqttPortLabel = $hostLastOctet !== ''
    ? $hostLastOctet . '01'
    : 'Unknown';

$mosquittoUsername = '';
$mosquittoPassword = '';
$mosquittoCredentialsFound = false;

if (is_readable($mosquittoCredentialsFile)) {
    $credentialsText = @file_get_contents(
        $mosquittoCredentialsFile
    );

    if (is_string($credentialsText) && $credentialsText !== '') {
        foreach (preg_split('/\r\n|\r|\n/', $credentialsText) as $line) {
            $line = trim($line);

            if (
                $mosquittoUsername === '' &&
                str_starts_with($line, 'username=')
            ) {
                $mosquittoUsername = trim(substr($line, 9));
            } elseif (
                $mosquittoPassword === '' &&
                str_starts_with($line, 'password=')
            ) {
                $mosquittoPassword = trim(substr($line, 9));
            }
        }

        $mosquittoCredentialsFound =
            $mosquittoUsername !== '' &&
            $mosquittoPassword !== '';
    }
}

$commandsWritable = is_dir($actionsDir) && is_writable($actionsDir);
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Meek.io Admin</title>

    <style>
        * {
            box-sizing: border-box;
        }

        body {
            margin: 0;
            padding: 30px;
            font-family: system-ui, -apple-system, BlinkMacSystemFont,
                "Segoe UI", sans-serif;
            background: #f1f5f9;
            color: #0f172a;
        }

        h1 {
            margin: 0 0 25px;
            font-size: 1.8rem;
        }

        .grid {
            display: grid;
            grid-template-columns:
                repeat(auto-fit, minmax(min(100%, 340px), 1fr));
            gap: 20px;
            max-width: 1400px;
            align-items: start;
        }

        .card {
            min-width: 0;
            padding: 22px;
            background: #fff;
            border-radius: 14px;
            box-shadow: 0 4px 14px rgba(15, 23, 42, 0.08);
        }

        h2 {
            margin: 0 0 18px;
            font-size: 1.25rem;
        }

        .category-header {
            display: flex;
            flex-wrap: wrap;
            justify-content: space-between;
            align-items: center;
            gap: 10px;
            margin-bottom: 16px;
        }

        .category-header h2 {
            margin: 0;
        }

        .service-link {
            display: inline-block;
            color: #2563eb;
            font-size: 0.85rem;
            font-weight: 600;
            text-decoration: none;
        }

        .service-link:hover {
            color: #1d4ed8;
            text-decoration: underline;
        }

        .button-row {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
        }

        form {
            margin: 0;
        }

        button {
            padding: 10px 16px;
            border: 0;
            border-radius: 8px;
            background: #2563eb;
            color: #fff;
            font-size: 0.9rem;
            cursor: pointer;
        }

        button:hover {
            background: #1d4ed8;
        }

        button:disabled {
            background: #cbd5e1;
            color: #475569;
            cursor: not-allowed;
        }

        .danger {
            background: #dc2626;
        }

        .danger:hover {
            background: #b91c1c;
        }

        button:focus-visible,
        input:focus-visible,
        summary:focus-visible,
        a:focus-visible {
            outline: 3px solid #93c5fd;
            outline-offset: 3px;
        }

        label {
            display: block;
            margin: 14px 0 6px;
            font-size: 0.9rem;
            font-weight: 600;
        }

        input:not([type="hidden"]) {
            display: block;
            width: 100%;
            min-width: 0;
            padding: 10px;
            border: 1px solid #cbd5e1;
            border-radius: 8px;
            font: inherit;
            font-size: 0.95rem;
            background: #fff;
            color: #0f172a;
        }

        .message {
            max-width: 1400px;
            margin-bottom: 20px;
            padding: 12px 16px;
            border-radius: 8px;
            line-height: 1.5;
        }

        .success {
            background: #dcfce7;
            color: #166534;
        }

        .error {
            background: #fee2e2;
            color: #991b1b;
        }

        .warning {
            background: #fef3c7;
            color: #92400e;
        }

        .info {
            margin: 0 0 15px;
            font-size: 0.85rem;
            line-height: 1.5;
            color: #64748b;
            overflow-wrap: anywhere;
        }

        .update-available {
            color: #b91c1c;
            font-weight: 700;
        }

        .up-to-date {
            color: #166534;
            font-weight: 700;
        }

        .status-unknown {
            color: #92400e;
            font-weight: 700;
        }

        .note {
            margin: 12px 0 0;
            font-size: 0.78rem;
            line-height: 1.5;
            color: #64748b;
        }

        .mosquitto-header {
            display: flex;
            justify-content: space-between;
            align-items: flex-start;
            gap: 16px;
            margin-bottom: 18px;
        }

        .mosquitto-header h2 {
            flex: 0 0 auto;
            margin: 0;
        }

        .mqtt-ports {
            flex: 0 1 240px;
            min-width: 0;
            margin-left: auto;
            text-align: left;
            font-size: 0.75rem;
            line-height: 1.5;
            color: #64748b;
            white-space: normal;
            overflow-wrap: break-word;
        }

        .mqtt-ports > div + div {
            margin-top: 5px;
        }

        .submit-row {
            margin-top: 18px;
        }

        .current-credentials {
            margin-top: 20px;
            padding: 14px;
            background: #f8fafc;
            border: 1px solid #e2e8f0;
            border-radius: 8px;
            font-size: 0.9rem;
            overflow-wrap: anywhere;
        }

        .current-credentials summary {
            cursor: pointer;
            font-weight: 600;
        }

        .current-credentials-label {
            font-weight: 600;
        }

        .current-credentials p:last-child {
            margin-bottom: 0;
        }

        @media (max-width: 700px) {
            body {
                padding: 18px;
            }

            .mosquitto-header {
                flex-direction: column;
                align-items: flex-start;
                gap: 10px;
            }

            .mqtt-ports {
                flex: 0 1 auto;
                width: 100%;
                margin-left: 0;
            }
        }
    </style>
</head>

<body>
    <h1>Meek.io Admin</h1>

    <?php if ($message !== ''): ?>
        <div class="message <?= escape($messageType) ?>" role="status">
            <?= escape($message) ?>
        </div>
    <?php endif; ?>

    <?php if (!$commandsWritable): ?>
        <div class="message error" role="alert">
            The commands directory is missing or not writable.
            Check the Docker volume mapping and directory permissions.
        </div>
    <?php endif; ?>

    <?php if ($handlerStale): ?>
        <div class="message warning" role="alert">
            The action handler has not reported in for a while.
            Queued actions may not run until it is restarted
            (<code>systemctl restart meek-action-handler</code>).
        </div>
    <?php endif; ?>

    <div class="grid">
        <?php foreach ($allowedActions as $category => $actions): ?>
            <section class="card">
                <div class="category-header">
                    <h2><?= escape($category) ?></h2>

                    <?php if (isset($serviceLinks[$category])): ?>
                        <a
                            class="service-link"
                            href="<?= escape($serviceLinks[$category]['url']) ?>"
                            target="_blank"
                            rel="noopener noreferrer"
                        >
                            <?= escape($serviceLinks[$category]['label']) ?> ↗
                        </a>
                    <?php endif; ?>
                </div>

                <?php if ($category === 'System'): ?>
                    <p class="info">
                        Manage the host system running Docker and all stacks.
                    </p>
                <?php elseif ($category === 'Zigbee2MQTT'): ?>
                    <p class="info">
                        Installed: <?= escape($zigbeeInstalled) ?><br>
                        Latest: <?= escape($zigbeeLatest) ?><br>
                        <span class="<?= escape($zigbeeStatus[0]) ?>">
                            <?= escape($zigbeeStatus[1]) ?>
                        </span>
                    </p>
                <?php elseif ($category === 'Node-RED'): ?>
                    <p class="info">
                        Installed: <?= escape($nodeRedInstalled) ?><br>
                        Latest: <?= escape($nodeRedLatest) ?><br>
                        <span class="<?= escape($nodeRedStatus[0]) ?>">
                            <?= escape($nodeRedStatus[1]) ?>
                        </span>
                    </p>
                <?php elseif ($category === 'Home Assistant'): ?>
                    <p class="info">
                        Installed: <?= escape($homeAssistantInstalled) ?><br>
                        Latest: <?= escape($homeAssistantLatest) ?><br>
                        <span class="<?= escape($homeAssistantStatus[0]) ?>">
                            <?= escape($homeAssistantStatus[1]) ?>
                        </span>
                    </p>
                <?php endif; ?>

                <div class="button-row">
                    <?php foreach ($actions as $action): ?>
                        <?php
                        $disabled = !$commandsWritable || (
                            $category === 'System' &&
                            $action === 'Update' &&
                            !$systemUpdateEnabled
                        );

                        $danger = in_array(
                            $action,
                            ['Stop', 'Reboot'],
                            true
                        );

                        $confirmText = '';

                        if ($category === 'System' && $action === 'Reboot') {
                            $confirmText = 'Reboot the host system? '
                                . 'All stacks on this host will be interrupted.';
                        } elseif ($action === 'Update' || $action === 'Stop') {
                            $confirmText = $action . ' ' . $category . '?';
                        }
                        ?>

                        <form
                            method="post"
                            action="/admin/"
                            <?php if ($confirmText !== ''): ?>
                                data-confirm="<?= escape($confirmText) ?>"
                            <?php endif; ?>
                        >
                            <input type="hidden" name="csrf"
                                value="<?= escape($_SESSION['csrf']) ?>">
                            <input type="hidden" name="category"
                                value="<?= escape($category) ?>">
                            <input type="hidden" name="button"
                                value="<?= escape($action) ?>">

                            <button
                                type="submit"
                                class="<?= $danger ? 'danger' : '' ?>"
                                <?= $disabled ? 'disabled' : '' ?>
                            >
                                <?= escape($action) ?>
                            </button>
                        </form>
                    <?php endforeach; ?>
                </div>

                <?php if ($category === 'System' && !$systemUpdateEnabled): ?>
                    <p class="note">
                        Host OS updates are disabled until the host update
                        command is configured.
                    </p>
                <?php endif; ?>
            </section>
        <?php endforeach; ?>

        <section class="card">
            <h2>Node-RED login</h2>

            <p class="info">
                Change the Node-RED editor username and password.
                Node-RED will restart after the change.
            </p>

            <form method="post" action="/admin/">
                <input type="hidden" name="csrf"
                    value="<?= escape($_SESSION['csrf']) ?>">
                <input type="hidden" name="category" value="Node-RED">
                <input type="hidden" name="button" value="SetCredentials">

                <label for="nodered_username">Username</label>
                <input
                    id="nodered_username"
                    name="username"
                    type="text"
                    autocomplete="username"
                    required
                >

                <label for="nodered_password">Password</label>
                <input
                    id="nodered_password"
                    name="password"
                    type="password"
                    autocomplete="new-password"
                    required
                >

                <label for="nodered_confirm">Confirm password</label>
                <input
                    id="nodered_confirm"
                    name="confirm_password"
                    type="password"
                    autocomplete="new-password"
                    required
                >

                <div class="submit-row">
                    <button type="submit" <?= !$commandsWritable ? 'disabled' : '' ?>>
                        Change Node-RED login
                    </button>
                </div>
            </form>
        </section>

        <section class="card">
            <h2>Home Assistant login</h2>

            <p class="info">
                Change the password of an existing Home Assistant user.
                Home Assistant will restart after the change.
            </p>

            <form
                method="post"
                action="/admin/"
                data-confirm="Change the Home Assistant password and restart Home Assistant?"
            >
                <input type="hidden" name="csrf"
                    value="<?= escape($_SESSION['csrf']) ?>">
                <input type="hidden" name="category" value="Home Assistant">
                <input type="hidden" name="button" value="SetPassword">

                <label for="ha_username">Username</label>
                <input
                    id="ha_username"
                    name="username"
                    type="text"
                    autocomplete="username"
                    required
                >

                <label for="ha_password">New password</label>
                <input
                    id="ha_password"
                    name="password"
                    type="password"
                    autocomplete="new-password"
                    required
                >

                <label for="ha_confirm">Confirm password</label>
                <input
                    id="ha_confirm"
                    name="confirm_password"
                    type="password"
                    autocomplete="new-password"
                    required
                >

                <div class="submit-row">
                    <button type="submit" <?= !$commandsWritable ? 'disabled' : '' ?>>
                        Change Home Assistant password
                    </button>
                </div>
            </form>
        </section>

        <section class="card">
            <h2>Zigbee2MQTT access</h2>

            <p class="info">
                Change the Zigbee2MQTT frontend access token.
                Zigbee2MQTT uses a token rather than a username and password.
                Zigbee2MQTT will restart after the change.
            </p>

            <form method="post" action="/admin/">
                <input type="hidden" name="csrf"
                    value="<?= escape($_SESSION['csrf']) ?>">
                <input type="hidden" name="category" value="Zigbee2MQTT">
                <input type="hidden" name="button" value="SetToken">

                <label for="zigbee_token">Access token</label>
                <input
                    id="zigbee_token"
                    name="token"
                    type="text"
                    autocomplete="off"
                    required
                >

                <label for="zigbee_token_confirm">Confirm token</label>
                <input
                    id="zigbee_token_confirm"
                    name="confirm_token"
                    type="text"
                    autocomplete="off"
                    required
                >

                <div class="submit-row">
                    <button type="submit" <?= !$commandsWritable ? 'disabled' : '' ?>>
                        Change Zigbee2MQTT token
                    </button>
                </div>
            </form>
        </section>

        <section class="card">
            <div class="mosquitto-header">
                <h2>Mosquitto</h2>

                <div class="mqtt-ports">
                    <div>Systemwide MQTT port 1883</div>
                    <div>Secure MQTT port <?= escape($secureMqttPortLabel) ?></div>
                    <div>Unsecure MQTT port <?= escape($unsecureMqttPortLabel) ?></div>
                </div>
            </div>

            <form
                method="post"
                action="/admin/"
                data-confirm="This replaces ALL MQTT users with this one account. Zigbee2MQTT, Node-RED and Home Assistant lose MQTT access unless they use these credentials. Continue?"
            >
                <input type="hidden" name="csrf"
                    value="<?= escape($_SESSION['csrf']) ?>">
                <input type="hidden" name="category" value="Mosquitto">
                <input type="hidden" name="button" value="AddUser">

                <label for="username">Username</label>
                <input
                    id="username"
                    name="username"
                    type="text"
                    autocomplete="username"
                    required
                >

                <label for="password">Password</label>
                <input
                    id="password"
                    name="password"
                    type="password"
                    autocomplete="new-password"
                    required
                >

                <label for="confirm_password">Confirm password</label>
                <input
                    id="confirm_password"
                    name="confirm_password"
                    type="password"
                    autocomplete="new-password"
                    required
                >

                <div class="submit-row">
                    <button type="submit" <?= !$commandsWritable ? 'disabled' : '' ?>>
                        Replace MQTT user
                    </button>
                </div>
            </form>

            <details class="current-credentials">
                <summary>Show current Mosquitto credentials</summary>

                <?php if ($mosquittoCredentialsFound): ?>
                    <p>
                        <span class="current-credentials-label">Username:</span>
                        <?= escape($mosquittoUsername) ?>
                    </p>

                    <p>
                        <span class="current-credentials-label">Password:</span>
                        <?= escape($mosquittoPassword) ?>
                    </p>

                    <p class="note">
                        These are the credentials currently recorded for Mosquitto.
                    </p>
                <?php else: ?>
                    <p>
                        No current Mosquitto credentials have been recorded yet.
                    </p>
                <?php endif; ?>
            </details>
        </section>
    </div>

    <script>
        document.querySelectorAll('form[data-confirm]').forEach(form => {
            form.addEventListener('submit', event => {
                if (!window.confirm(form.dataset.confirm)) {
                    event.preventDefault();
                }
            });
        });

        // After a queued action, reload every 5 seconds for about a minute
        // so the new version numbers appear. Skipped while typing in a field.
        (function () {
            const key = 'meekRefreshes';
            let left = parseInt(sessionStorage.getItem(key) || '0', 10);

            <?php if ($refresh): ?>
            left = 12;
            <?php endif; ?>

            if (left > 0) {
                sessionStorage.setItem(key, String(left - 1));

                setTimeout(function () {
                    const active = document.activeElement;

                    if (!active || active.tagName !== 'INPUT') {
                        location.reload();
                    }
                }, 5000);
            }
        })();
    </script>
</body>
</html>
