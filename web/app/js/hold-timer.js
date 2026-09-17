import * as C from './core.js';
import * as ui from './ui.js';

// One continuous attempt. The set is untouched until onSave succeeds.
export function openHoldTimer({ exerciseName, seconds, onSave, onStart = () => {}, onDone = () => {} }) {
  const now = () => Date.now() / 1000;
  const target = Math.min(1800, Math.max(1, Number.isFinite(seconds) ? Math.floor(seconds) : 30));
  let clock = C.holdClockStart(target, now()), handle, closed = false, saving = false;
  let countdown, status, stopButton, logButton, restartButton, errorLabel, api;
  function stop() {
    clock = C.holdClockStop(clock, now());
    clearInterval(handle);
    paint();
  }
  function paint() {
    if (closed) return;
    const remaining = C.holdClockRemaining(clock, now());
    const running = clock.stoppedEpoch == null;
    const elapsed = C.holdClockLoggedSeconds(clock, now());
    countdown.textContent = ui.mmss(running ? remaining : elapsed);
    countdown.setAttribute('aria-label', `${running ? 'Hold time remaining' : 'Time held'}: ${running ? remaining : elapsed} seconds`);
    status.textContent = running ? 'HOLD' : remaining === 0 ? 'HOLD COMPLETE' : 'STOPPED';
    stopButton.hidden = !running;
    logButton.hidden = running;
    logButton.textContent = `Log ${C.cardioDurationLabel(elapsed)}`;
    logButton.disabled = saving || elapsed === 0;
    restartButton.hidden = running;
    restartButton.disabled = saving;
  }
  function tick() {
    if (closed) return;
    if (clock.stoppedEpoch == null && C.holdClockRemaining(clock, now()) === 0) {
      stop(); onDone();
    } else paint();
  }
  function startTicks() { clearInterval(handle); handle = setInterval(tick, 200); }
  api = ui.sheet({
    title: `${exerciseName} · hold timer`,
    canClose: () => !saving,
    onClose: () => {
      closed = true; clearInterval(handle);
      document.removeEventListener('visibilitychange', tick);
    },
    build: (body, sheet) => {
      status = ui.h('div', { class: 'eyebrow', role: 'status' });
      countdown = ui.h('div', { class: 'hold-countdown mono', role: 'timer' });
      stopButton = ui.h('button', { class: 'btn primary wide', text: 'Stop hold', onClick: stop });
      logButton = ui.h('button', { class: 'btn primary wide', onClick: async () => {
        if (saving || clock.stoppedEpoch == null) return;
        const elapsed = C.holdClockLoggedSeconds(clock, now());
        if (elapsed === 0) return;
        saving = true; errorLabel.textContent = ''; paint();
        try { await onSave(elapsed); saving = false; sheet.close(); }
        catch { saving = false; errorLabel.textContent = 'Could not save the hold. Your timed result is still here; try again.'; paint(); }
      } });
      restartButton = ui.h('button', { class: 'btn wide', text: 'Try again', onClick: () => {
        clock = C.holdClockStart(target, now()); errorLabel.textContent = ''; onStart(); startTicks(); paint();
      } });
      errorLabel = ui.h('p', { role: 'alert' });
      body.append(ui.h('div', { class: 'hold-timer', 'data-testid': 'hold-timer' },
        status, countdown, ui.h('p', { class: 'sub', text: `Target ${C.cardioDurationLabel(target)}` }),
        stopButton, logButton, restartButton,
        ui.h('p', { class: 'sub', text: 'Log records this attempt and completes the set. Closing leaves the set unchanged.' }),
        errorLabel, ui.h('button', { class: 'btn ghost wide', text: 'Discard attempt', onClick: () => sheet.close() })));
    },
  });
  onStart(); paint(); startTicks();
  document.addEventListener('visibilitychange', tick);
  return api;
}
