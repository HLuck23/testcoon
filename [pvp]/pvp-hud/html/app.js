// ============================================================
// PVP HUD JAVASCRIPT - Purple Theme Edition
// ============================================================

const $ = (id) => document.getElementById(id);

let playerSource = 0;

// ============================================================
// NUI MESSAGE LISTENER
// ============================================================

window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data.action) return;

    switch (data.action) {
        case 'setSource':
            playerSource = data.source || 0;
            break;

        case 'updateHealthArmor':
            updateHealthArmor(data);
            break;
        case 'showHealthArmor':
            showElement('health-armor-bar');
            break;
        case 'hideHealthArmor':
            hideElement('health-armor-bar');
            break;

        case 'updateAmmoHud':
            updateAmmoHud(data);
            break;
        case 'hideAmmoHud':
            hideElement('ammo-hud');
            break;

        case 'showMatchInfo':
            showMatchInfo(data);
            break;
        case 'hideMatchInfo':
            hideElement('match-info');
            break;
        case 'updateScore':
            updateScore(data.scores);
            break;
        case 'updateTimer':
            updateTimer(data.time);
            break;

        case 'showCountdown':
            showCountdown(data);
            break;
        case 'hideCountdown':
            hideElement('countdown');
            break;
        case 'countdownTick':
            countdownTick(data.time);
            break;

        case 'showMatchEnd':
            showMatchEnd(data);
            break;
        case 'hideMatchEnd':
            hideElement('match-end');
            break;

        case 'killFeed':
            addKillFeed(data);
            break;

        case 'showScoreboard':
            showElement('scoreboard');
            break;
        case 'hideScoreboard':
            hideElement('scoreboard');
            break;
        case 'updateScoreboard':
            updateScoreboard(data.players);
            if (data.mode) $('sb-mode').textContent = data.mode.toUpperCase();
            break;

        case 'showLobby':
            showElement('lobby');
            updateLobby(data);
            break;
        case 'hideLobby':
            hideElement('lobby');
            break;

        case 'showStreak':
            showStreak(data);
            break;
    }
});

// ============================================================
// HEALTH & ARMOR - Premium Vertical Lines
// ============================================================

function updateHealthArmor(data) {
    const hp = data.health || 0;
    const armor = data.armor || 0;
    const maxHp = data.maxHealth || 100;
    const maxArmor = 100;

    $('hp-value').textContent = hp;
    $('armor-value').textContent = armor;

    const hpPct = Math.max(0, Math.min(100, (hp / maxHp) * 100));
    const armorPct = Math.max(0, Math.min(100, (armor / maxArmor) * 100));

    const hpLineHeight = Math.max(3, Math.round((hpPct / 100) * 44));
    const armorLineHeight = Math.max(3, Math.round((armorPct / 100) * 44));

    const hpLine = $('hp-vline');
    const armorLine = $('armor-vline');
    const hpFill = $('hp-fill');
    const armorFill = $('armor-fill');

    if (hpFill) hpFill.style.height = hpLineHeight + 'px';
    if (armorFill) armorFill.style.height = armorLineHeight + 'px';

    if (hpPct <= 25) {
        hpLine.classList.add('critical');
        $('hp-value').style.color = 'rgba(255, 70, 70, 0.95)';
        $('hp-value').style.textShadow = '0 0 12px rgba(255, 50, 50, 0.5)';
    } else if (hpPct <= 50) {
        hpLine.classList.remove('critical');
        $('hp-value').style.color = 'rgba(255, 190, 120, 0.95)';
        $('hp-value').style.textShadow = '0 0 8px rgba(255, 170, 80, 0.3)';
    } else {
        hpLine.classList.remove('critical');
        $('hp-value').style.color = 'rgba(255, 130, 130, 0.95)';
        $('hp-value').style.textShadow = '0 0 10px rgba(255, 68, 68, 0.35)';
    }

    if (armor <= 0) {
        armorLine.classList.add('empty');
        $('armor-value').style.color = 'rgba(150, 150, 150, 0.35)';
        $('armor-value').style.textShadow = 'none';
    } else if (armorPct <= 25) {
        armorLine.classList.remove('empty');
        $('armor-value').style.color = 'rgba(210, 150, 255, 0.95)';
        $('armor-value').style.textShadow = '0 0 8px rgba(180, 120, 255, 0.3)';
    } else {
        armorLine.classList.remove('empty');
        $('armor-value').style.color = 'rgba(130, 180, 255, 0.95)';
        $('armor-value').style.textShadow = '0 0 10px rgba(68, 136, 255, 0.35)';
    }
}

// ============================================================
// WEAPON / AMMO HUD — only visible while a gun is out
// ============================================================

function updateAmmoHud(data) {
    const name = (data.weaponName || 'Weapon').toUpperCase();
    const ammo = Math.max(0, data.ammo || 0);
    const maxAmmo = Math.max(1, data.maxAmmo || 1);

    $('ammo-weapon-name').textContent = name;
    $('ammo-count').textContent = ammo;

    const pct = Math.max(0, Math.min(100, (ammo / maxAmmo) * 100));
    const fill = $('ammo-bar-fill');
    if (fill) {
        fill.style.width = pct + '%';
        fill.classList.toggle('low', pct <= 20);
    }

    const indicator = $('ammo-bar-indicator');
    if (indicator) {
        indicator.style.left = pct + '%';
    }

    showElement('ammo-hud');
}

// ============================================================
// MATCH INFO
// ============================================================

function showMatchInfo(data) {
    $('match-mode').textContent = (data.mode || 'REDZONE').toUpperCase();
    showElement('match-info');
}

function updateScore(scores) {
    if (!scores) return;
    $('match-score').textContent = `${scores.teamA || 0} - ${scores.teamB || 0}`;
}

function updateTimer(time) {
    if (time === undefined) return;
    const m = Math.floor(time / 60), s = time % 60;
    $('match-timer').textContent = `${m}:${s.toString().padStart(2, '0')}`;
}

// ============================================================
// COUNTDOWN
// ============================================================

function showCountdown(data) {
    $('countdown-mode').textContent = (data.mode || 'REDZONE').toUpperCase();
    $('countdown-number').textContent = data.timer || 5;
    showElement('countdown');
}

function countdownTick(t) {
    $('countdown-number').textContent = t;
}

// ============================================================
// MATCH END
// ============================================================

function showMatchEnd(data) {
    $('end-winner').textContent = data.winnerName ? `${data.winnerName} WINS!` : 'MATCH OVER';
    if (data.scores) {
        $('end-scores').textContent = `Score: ${data.scores.teamA || 0} - ${data.scores.teamB || 0}`;
    } else {
        $('end-scores').textContent = '';
    }
    if (data.stats) {
        $('end-stats').textContent = data.stats;
    } else {
        $('end-stats').textContent = '';
    }
    showElement('match-end');
}

// ============================================================
// KILL FEED
// ============================================================

function addKillFeed(data) {
    const feed = $('kill-feed');
    const entry = document.createElement('div');
    entry.className = 'kill-entry';
    const weapon = data.weapon ? `<span class="kill-weapon"> [${esc(data.weapon)}] </span>` : '<span class="kill-weapon"> killed </span>';
    entry.innerHTML = `
        <span class="kill-killer">${esc(data.killer || 'Unknown')}</span>
        ${weapon}
        <span class="kill-victim">${esc(data.victim || 'Unknown')}</span>
    `;
    feed.appendChild(entry);
    setTimeout(() => { if (entry.parentNode) entry.parentNode.removeChild(entry); }, 6000);
    while (feed.children.length > 6) feed.removeChild(feed.firstChild);
}

// ============================================================
// SCOREBOARD — sorted by K/D ratio (best at top)
// ============================================================

function getKD(p) {
    const k = p.kills || 0;
    const d = p.deaths || 0;
    if (d > 0) return k / d;
    if (k > 0) return k * 1.0;
    return 0;
}

function updateScoreboard(players) {
    const table = $('sb-table');
    table.innerHTML = '';
    if (!players || players.length === 0) {
        table.innerHTML = '<div class="sb-row"><span style="color:#888;text-align:center;width:100%;">No players</span></div>';
        return;
    }
    [...players].sort((a, b) => {
        return getKD(b) - getKD(a);
    }).forEach((p) => {
        const row = document.createElement('div');
        row.className = 'sb-row' + (p.source === playerSource ? ' self' : '');
        row.innerHTML = `
            <span class="sb-rank">${p.source || '?'}</span>
            <span class="sb-name">${esc(p.name || 'Unknown')}</span>
            <span class="sb-kills">${p.kills || 0}</span>
            <span class="sb-deaths">${p.deaths || 0}</span>
            <span class="sb-ping">${p.ping || 0}ms</span>
        `;
        table.appendChild(row);
    });
}

// ============================================================
// LOBBY
// ============================================================

function updateLobby(data) {
    const current = data.players || 0;
    const min = data.minPlayers || 1;
    const max = data.maxPlayers || min;
    $('lobby-count').textContent = `${current} / ${max}`;
    const bar = $('lobby-progress-bar');
    if (bar) {
        const pct = Math.min(100, (current / max) * 100);
        bar.style.width = pct + '%';
    }
}

// ============================================================
// KILL STREAK MEDALS - Clean, under match timer
// ============================================================

function showStreak(data) {
    const container = $('streak-medals');
    const el = document.createElement('div');
    el.className = 'streak-medal';
    el.innerHTML = `
        <img src="streaks/${esc(data.medal)}" alt="${esc(data.label)}" onerror="this.style.display='none'">
        <div class="streak-label">${esc(data.label)}</div>
    `;
    container.appendChild(el);
    setTimeout(() => { if (el.parentNode) el.parentNode.removeChild(el); }, 3100);
    while (container.children.length > 1) container.removeChild(container.firstChild);
}

// ============================================================
// UTILITIES
// ============================================================

function showElement(id) { const el = $(id); if (el) el.classList.remove('hidden'); }
function hideElement(id) { const el = $(id); if (el) el.classList.add('hidden'); }
function esc(t) { if (!t) return ''; const d = document.createElement('div'); d.textContent = t; return d.innerHTML; }

// Hide ALL overlays on load -- health/armor bar included. It only
// belongs to Redzone/Turf Wars and must wait for that state, same as
// everything else here. Leaving it always-on was exactly what bled
// this resource's HUD onto every other game mode (Wars, Hub, etc).
window.addEventListener('DOMContentLoaded', () => {
    ['match-info', 'countdown', 'match-end', 'scoreboard', 'lobby', 'ammo-hud', 'health-armor-bar'].forEach(hideElement);
});