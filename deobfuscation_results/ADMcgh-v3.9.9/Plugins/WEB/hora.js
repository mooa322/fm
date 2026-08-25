// script.js

function updateClock() {
    const now = new Date();
    const date = now.toLocaleDateString('es-ES'); // Formato de fecha específico (puedes ajustarlo)
    const time = now.toLocaleTimeString('es-ES'); // Formato de hora específico (puedes ajustarlo)

    const clockElement = document.getElementById('clock');
    clockElement.textContent = `Fecha: ${date}, Hora: ${time}`;
}

// Actualizar el reloj cada segundo
setInterval(updateClock, 1000);
