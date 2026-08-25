#!/usr/bin/env python3
import os
import sys
import time
import subprocess
from platform import system

# ================= Dependencias =================
USE_RICH = False
USE_REQUESTS = False

try:
    import requests
    USE_REQUESTS = True
except ImportError:
    import urllib.request as urllib

try:
    from rich.console import Console
    from rich.table import Table
    from rich.prompt import Prompt
    USE_RICH = True
    console = Console()
except ImportError:
    # Colores básicos con ANSI
    class FakeConsole:
        def print(self, text, style=None):
            print(text)
        def rule(self, text=""):
            print("="*40, text, "="*40)
    console = FakeConsole()

# ================= Utilidades =================
def clear():
    if system() == 'Linux':
        os.system("clear")
    elif system() == 'Windows':
        os.system("cls")
        os.system("color a")

def slowprint(s, delay=0.03):
    for c in s + '\n':
        sys.stdout.write(c)
        sys.stdout.flush()
        time.sleep(delay)

# ================= Banner =================
banner = """
\033[96m
████████╗ ██████╗  ██████╗ ██╗     ███╗   ███╗ █████╗ ███████╗████████╗███████╗██████╗ 
╚══██╔══╝██╔═══██╗██╔═══██╗██║     ████╗ ████║██╔══██╗██╔════╝╚══██╔══╝██╔════╝██╔══██╗
   ██║   ██║   ██║██║   ██║██║     ██╔████╔██║███████║███████╗   ██║   █████╗  ██████╔╝
   ██║   ██║   ██║██║   ██║██║     ██║╚██╔╝██║██╔══██║╚════██║   ██║   ██╔══╝  ██╔═══╝ 
   ██║   ╚██████╔╝╚██████╔╝███████╗██║ ╚═╝ ██║██║  ██║███████║   ██║   ███████╗██║     
   ╚═╝    ╚═════╝  ╚═════╝ ╚══════╝╚═╝     ╚═╝╚═╝  ╚═╝╚══════╝   ╚═╝   ╚══════╝╚═╝     
\033[0m
=============== ToolMaster Modernizado ===============
============== by @ChumoGH | chumogh.xyz ==============
"""

# ================= Opciones =================
tools = {
    "1": ("DNS Lookup", "dnslookup"),
    "2": ("Whois Lookup", "whois"),
    "3": ("Reverse IP Lookup", "reverseiplookup"),
    "4": ("GeoIP Lookup", "geoip"),
    "5": ("Subnet Lookup", "subnetcalc"),
    "6": ("Port Scanner", "nmap"),
    "7": ("Extract Links", "pagelinks"),
    "8": ("Zone Transfer", "zonetransfer"),
    "9": ("HTTP Header", "httpheaders"),
    "10": ("Host Finder", "hostsearch"),
    "11": ("Info", None),
    "0": ("Salir", None),
}

API_URL = "http://api.hackertarget.com/"

# ================= Menú =================
def menu():
    if USE_RICH:
        table = Table(title="Menú de Opciones", show_header=True, header_style="bold cyan")
        table.add_column("Nº", justify="center", style="bold yellow")
        table.add_column("Herramienta", justify="left", style="bold green")
        for k, v in tools.items():
            table.add_row(k, v[0])
        console.print(table)
    else:
        print("\n===== Menú de Opciones =====")
        for k, v in tools.items():
            print(f" {k}) {v[0]}")

# ================= API Query =================
def consulta_api(endpoint, target):
    url = f"{API_URL}{endpoint}/?q={target}"
    #console.print(f"\n[Consulta a]: {url}\n")

    try:
        if USE_REQUESTS:
            r = requests.get(url, timeout=10)
            if r.status_code == 200:
                console.rule(" Resultado ")
                console.print(r.text)
                console.rule(" Fin del resultado ")
            else:
                console.print(f"[ERROR {r.status_code}] No se pudo completar la consulta")
        else:
            with urllib.urlopen(url) as response:
                data = response.read().decode()
                console.rule(" Resultado ")
                console.print(data)
                console.rule(" Fin del resultado ")
    except Exception as e:
        console.print(f"[x] Error: {e}")

# ================= Lógica principal =================
def main():
    clear()
    console.print(banner)
    while True:
        menu()
        if USE_RICH:
            choice = Prompt.ask("[cyan]Elige una opción[/cyan]", choices=list(tools.keys()))
        else:
            choice = input("Elige una opción: ").strip()
            if choice not in tools:
                print("Opción inválida")
                continue

        if choice == "0":
            console.print("Saliendo... ¡Hasta pronto!")
            sys.exit(0)
        elif choice == "11":
            slowprint("ToolMaster Modernizado por @ChumoGH", 0.05)
            slowprint("Website: chumogh.xyz", 0.05)
        else:
            target = input(f"Ingrese dominio/IP para {tools[choice][0]}: ").strip()
            consulta_api(tools[choice][1], target)
        print("\n------------------------------------------\n")

if __name__ == "__main__":
    main()
