from os import listdir
from pathlib import Path
from re import compile
from statistics import mean, stdev, median
import matplotlib.pyplot as plt
import sys


def generate_figures():
    data = load_raw_data()
    generate_figures_for_behaviour_observation(data)
    generate_figures_for_average_behaviour_observation(data)
    generate_figures_for_time_performance_discussion(data)
    generate_figures_for_space_performance_discussion(data)


# --------------------------------------------------------------------------------------
def generate_figures_for_behaviour_observation(data):
    for bench, dct in data.items():
        _generate_figures_for_behaviour_observation(bench, dct["rem-refs"])


def _generate_figures_for_behaviour_observation(bench, data):
    max_n = min(len(data[mode]) for mode in data.keys())
    if max_n < 15:
        insufficient_modes = ['{}/{}'.format(bench, mode) for mode in data.keys() if len(data[mode]) < 15]
        print('warning: data may not be sufficient -- {}'.format(' '.join(insufficient_modes)), file=sys.stderr)
    for n in range(max_n):
        plt.clf()
        plt.rcParams["font.size"] = 18
        plt.xlabel("# of Iterations")
        plt.ylabel("# of Remote References")
        plt.ticklabel_format(axis="y", style='sci', scilimits=(0, 0))
        plt.subplots_adjust(left=0.15, right=0.95, top=0.80, bottom=0.15)
        for i, mode in enumerate(["rggc", "no-rggc", "naive-rggc"]):
            if mode in data:
                # > use the following if we show error bars
                # ls = list(map(stat_vals, zip(*data[mode])))
                # ys = [e["mean"] for e in ls]
                # es = [e["stdev"] for e in ls]
                # xs = list(range(1, len(ys) + 1))
                # mk = ["o", "s", "x"][i]
                # plt.errorbar(
                #     xs, ys,
                #     yerr=es,
                #     marker=mk,
                #     label=mode,
                #     capsize=5,
                # )
                # > use the following if we don't show error bars
                ys = data[mode][n]
                xs = list(range(1, len(ys) + 1))
                mk = ["o", "s", "x"][i]
                plt.plot(xs, ys, marker=mk, label=mode)
        plt.legend(loc="upper center", bbox_to_anchor=(0.5, 1.3), ncol=3, fontsize=15)
        plt.savefig(OUT_DIR / f"behaviour-{bench}-{n}.pdf")


# --------------------------------------------------------------------------------------
def generate_figures_for_average_behaviour_observation(data):
    for bench, dct in data.items():
        _generate_figures_for_average_behaviour_observation(bench, dct["rem-refs"])


def _generate_figures_for_average_behaviour_observation(bench, data):
    plt.clf()
    plt.rcParams["font.size"] = 18
    plt.xlabel("# of Iterations")
    plt.ylabel("# of Remote References")
    plt.ticklabel_format(axis="y", style='sci', scilimits=(0, 0))
    plt.subplots_adjust(left=0.15, right=0.95, top=0.80, bottom=0.15)
    for i, mode in enumerate(["rggc", "no-rggc", "naive-rggc"]):
        if mode in data:
            ys = list(map(mean, zip(*data[mode])))
            xs = list(range(1, len(ys) + 1))
            mk = ["o", "s", "x"][i]
            plt.plot(xs, ys, marker=mk, label=mode)
    plt.legend(loc="upper center", bbox_to_anchor=(0.5, 1.3), ncol=3, fontsize=15)
    plt.savefig(OUT_DIR / f"average-behaviour-{bench}.pdf")



# --------------------------------------------------------------------------------------
def generate_figures_for_time_performance_discussion(data):
    for bench, dct in data.items():
        _generate_figure_for_time_performance_discussion(bench, dct)


def _generate_figure_for_time_performance_discussion(bench, data):
    data = _reorganize_time_data(data)

    rggc_run = data["rggc"]["run-time"]
    rggc_rbgc = data["rggc"]["rbgc-time"]
    rggc_rggc = data["rggc"]["rggc-time"]
    rggc_nongc = data["rggc"]["nongc-time"]

    naive_rggc_run = data["naive-rggc"]["run-time"]
    naive_rggc_rbgc = data["naive-rggc"]["rbgc-time"]
    naive_rggc_rggc = data["naive-rggc"]["rggc-time"]
    naive_rggc_nongc = data["naive-rggc"]["nongc-time"]

    no_rggc_run = data["no-rggc"]["run-time"]
    no_rggc_rbgc = data["no-rggc"]["rbgc-time"]
    no_rggc_nongc = data["no-rggc"]["nongc-time"]

    plt.clf()
    plt.rcParams["font.size"] = 18
    plt.ylabel("Time (s)")
    plt.ticklabel_format(axis="y", style='sci', scilimits=(0, 0))
    plt.subplots_adjust(left=0.15, right=0.95, top=0.85, bottom=0.10)
    plt.bar(
        [-0.2, 1, 2.4, 3.8],
        [rggc_rggc["median"], rggc_rbgc["median"], rggc_nongc["median"], rggc_run["median"]],
        yerr=[rggc_rggc["stdev"], rggc_rbgc["stdev"], rggc_nongc["stdev"], rggc_run["stdev"]],
        label="rggc", capsize=3, width=0.4
    )
    plt.bar(
        [1.4, 2.8, 4.2],
        [no_rggc_rbgc["median"], no_rggc_nongc["median"], no_rggc_run["median"]],
        yerr=[no_rggc_rbgc["stdev"], no_rggc_nongc["stdev"], no_rggc_run["stdev"]],
        label="no-rggc", capsize=3, width=0.4
    )
    plt.bar(
        [0.2, 1.8, 3.2, 4.6],
        [naive_rggc_rggc["median"], naive_rggc_rbgc["median"], naive_rggc_nongc["median"], naive_rggc_run["median"]],
        yerr=[naive_rggc_rggc["stdev"], naive_rggc_rbgc["stdev"], naive_rggc_nongc["stdev"], naive_rggc_run["stdev"]],
        label="naive-rggc", capsize=3, width=0.4
    )
    plt.xticks([0, 1.4, 2.8, 4.2], ["rggc", "rbgc", "non-gc", "total"])
    plt.legend(loc="upper center", bbox_to_anchor=(0.5, 1.2), ncol=3, fontsize=15)
    plt.savefig(OUT_DIR / f"time-{bench}.pdf")


def _reorganize_time_data(data):
    data = {
        seg: {
            mode: list(map(sum, lsts))
            for mode, lsts in dct.items()
        } for seg, dct in data.items()
    }
    for mode in data["run-time"]:
        run = data["run-time"][mode]
        rbgc = data["rbgc-time"][mode]
        rggc = data["rggc-time"][mode]
        d = data.setdefault("nongc-time", {})
        d[mode] = [t1-t2-t3 for t1, t2, t3 in zip(run, rbgc, rggc)]
    data = {
        seg: {mode: stat_vals(lst) for mode, lst in dct.items()}
        for seg, dct in data.items()
    }
    ret = {}
    for seg, dct1 in data.items():
        for mode, dct2 in dct1.items():
            d = ret.setdefault(mode, {})
            d[seg] = {k: v/1000 for k, v in dct2.items()}
    return ret


# --------------------------------------------------------------------------------------
def generate_figures_for_space_performance_discussion(data):
    for bench, dct in data.items():
        _generate_figure_for_space_performance_discussion(bench, "rb", dct["heap-rb"])


def _generate_figure_for_space_performance_discussion(bench, seg, data):
    data = {mode: list(map(stat_vals, zip(*lsts))) for mode, lsts in data.items()}
    plt.clf()
    plt.rcParams["font.size"] = 18
    plt.xlabel("# of Iterations")
    plt.ylabel("Heap Size (MB)")
    plt.ticklabel_format(axis="y", style='sci', scilimits=(0, 0))
    plt.subplots_adjust(left=0.15, right=0.95, top=0.80, bottom=0.15)
    for i, mode in enumerate(["rggc", "no-rggc", "naive-rggc"]):
        if mode in data:
            ys = [e["mean"] for e in data[mode]]
            es = [e["stdev"] for e in data[mode]]
            xs = list(range(1, len(ys) + 1))
            mk = ["o", "s", "x"][i]
            plt.errorbar(xs, ys, yerr=es, label=mode, marker=mk, capsize=3)
    plt.legend(loc="upper center", bbox_to_anchor=(0.5, 1.3), ncol=3, fontsize=15)
    plt.savefig(OUT_DIR / f"space-{bench}-{seg}.pdf")


# --------------------------------------------------------------------------------------
def stat_vals(lst):
    return dict(
        min=min(lst), max=max(lst),
        mean=mean(lst), median=median(lst),
        stdev=stdev(lst) if 1 < len(lst) else 0
    )


# --------------------------------------------------------------------------------------
def load_raw_data():
    data = {}
    for b, m, i, t in sorted(_read_raw_data()):
        for k, v in _parse_raw_data(t):
            dct = data.setdefault(b, {})
            dct = dct.setdefault(k, {})
            lst = dct.setdefault(m, [])
            len(lst) < i and lst.append([])
            lst[-1].append(v)
    return data


def _read_raw_data():
    for name in listdir(RAW_DIR):
        if name.endswith(".txt"):
            path = RAW_DIR / name
            b, m, i = path.with_suffix("").name.split("_")
            yield b, m, int(i), path.read_text()


def _parse_raw_data(data):
    for line in data.splitlines():
        if line.startswith("total time"):
            x, y = _find_matches(_run_time, line)
            yield "run-time", _fix_time_unit(x, y)
        elif line.startswith("gc time"):
            x, y = _find_matches(_rbgc_time, line)
            yield "rbgc-time", _fix_time_unit(x, y)
        elif line.startswith("reclaimed"):
            x, y = map(float, _find_matches(_heap_size, line))
            yield "heap-rb", x
            yield "heap-js", y
            yield "heap-sum", x + y
        elif line.startswith("Refgraph-gc"):
            x, y = _find_matches(_rggc_time, line)
            yield "rggc-time", _fix_time_unit(x, y)
        elif line.startswith("["):
            x, y, z = map(int, _find_matches(_rem_refs, line))
            yield "rem-refs", x + y + z


def _find_matches(pat, line):
    return next(pat.finditer(line)).groups()


def _fix_time_unit(x, y):
    return int(float(x) * (1 if y else 1000))


_run_time = compile(r"^total time: ([\d\.]+) (m?)sec\.$")

_rbgc_time = compile(r"^gc time: ([\d\.]+) (m?)sec\.$")

_rggc_time = compile(r"Refgraph-gc count: \d+, time: ([\d\.]+) (m?)sec\.$")

_heap_size = compile(r"reclaimed=\d+\. Rb=([\d\.]+)Mb, Js=([\d\.]+)Mb$")

_rem_refs = compile(r'^\[(\d+), (\d+), (\d+), "import/import-zombi/export"\]$')

# --------------------------------------------------------------------------------------
RAW_DIR = Path(__file__).parent / "raw"

OUT_DIR = Path(__file__).parent / "out"

if __name__ == "__main__":
    generate_figures()
