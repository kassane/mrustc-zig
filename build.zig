const std = @import("std");
const fixtures = @import("tests/fixtures.zig");

const mrustc_rev = "be69c7479a10bdce1b86cb886789d14a143ddf34";
const mrustc_target_ver = "1.74";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const build_minicargo = b.option(bool, "minicargo", "build the minicargo") orelse true;
    const mrustc = b.dependency("mrustc", .{});

    const zlib = b.dependency("zlib", .{
        .target = target,
        .optimize = optimize,
    }).artifact("z");
    zlib.root_module.sanitize_c = .off;

    const common = b.addLibrary(.{
        .name = "common",
        .linkage = .static,
        .root_module = cxxModule(b, target, optimize),
    });
    addCxxSources(common.root_module, mrustc.path("tools/common"), &.{
        "toml.cpp",
        "path.cpp",
        "debug.cpp",
        "jobserver.cpp",
    });
    common.root_module.addIncludePath(mrustc.path("tools/common"));

    const mrustc_exe = b.addExecutable(.{
        .name = "mrustc",
        .root_module = cxxModule(b, target, optimize),
    });
    addCxxSources(mrustc_exe.root_module, mrustc.path("src"), &mrustc_srcs);
    for ([_][]const u8{ "src/include", "src", "tools/common" }) |inc| {
        mrustc_exe.root_module.addIncludePath(mrustc.path(inc));
    }
    // version.cpp reads its build metadata from -D defines (upstream's Makefile
    // injects these from `git`). `addCMacro` is the idiomatic way to do that;
    // we stamp the pinned revision so the package is reproducible.
    stampVersion(mrustc_exe.root_module);
    mrustc_exe.root_module.linkLibrary(common);
    mrustc_exe.root_module.linkLibrary(zlib);
    b.installArtifact(mrustc_exe);

    const minicargo_exe = if (build_minicargo) blk: {
        const exe = b.addExecutable(.{
            .name = "minicargo",
            .root_module = cxxModule(b, target, optimize),
        });
        addCxxSources(exe.root_module, mrustc.path("tools/minicargo"), &minicargo_srcs);
        exe.root_module.addIncludePath(mrustc.path("tools/common"));
        exe.root_module.linkLibrary(common);
        b.installArtifact(exe);

        const run = b.addRunArtifact(exe);
        run.addArg("--help");
        b.step("minicargo", "Build and run minicargo (--help)").dependOn(&run.step);
        break :blk exe;
    } else null;

    const zigcc = buildZigCxxWrapper(
        b,
        optimize,
        target.query.zigTriple(b.allocator) catch @panic("OOM"),
    );
    b.installArtifact(zigcc);

    const expect_fail = b.addExecutable(.{
        .name = "expect-fail",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = optimize,
            .link_libc = true,
            .sanitize_c = .off,
        }),
    });
    expect_fail.root_module.addCSourceFile(.{ .file = b.path("tools/expect-fail.c"), .flags = &.{"-std=c99"} });

    const run = b.addRunArtifact(mrustc_exe);
    run.addArg("--version");
    b.step("run", "Build and run mrustc (--version)").dependOn(&run.step);

    const test_step = b.step("test", "Run the mrustc behaviour suite (95+ cases)");

    const t_version = b.addRunArtifact(mrustc_exe);
    t_version.setEnvironmentVariable("MRUSTC_TARGET_VER", mrustc_target_ver);
    t_version.addArg("--version");
    t_version.expectExitCode(0);
    t_version.expectStdOutMatch("rustc 1."); // rustc-compatible prefix
    t_version.expectStdOutMatch("mrustc v0.12"); // upstream version.cpp
    t_version.expectStdOutMatch(mrustc_rev); // our injected commit define
    test_step.dependOn(&t_version.step);

    const t_vv = b.addRunArtifact(mrustc_exe);
    t_vv.setEnvironmentVariable("MRUSTC_TARGET_VER", mrustc_target_ver);
    t_vv.addArg("-vV");
    t_vv.expectExitCode(0);
    t_vv.expectStdOutMatch("binary: rustc");
    t_vv.expectStdOutMatch(mrustc_rev); // commit-hash: <rev>
    test_step.dependOn(&t_vv.step);

    const t_help = b.addRunArtifact(mrustc_exe);
    t_help.addArg("--help");
    t_help.expectExitCode(0);
    t_help.expectStdOutMatch("USAGE: mrustc");
    test_step.dependOn(&t_help.step);

    // --- fixture-driven stage tests (lists from tests/fixtures.zig) ----------
    addStageTests(b, test_step, mrustc_exe, expect_fail, &fixtures.parse, "parse", .pass);
    addStageTests(b, test_step, mrustc_exe, expect_fail, &fixtures.parse_fail, "parse", .fail);
    addStageTests(b, test_step, mrustc_exe, expect_fail, &fixtures.no_core, "expand", .pass);
    addStageTests(b, test_step, mrustc_exe, expect_fail, &fixtures.no_core, "resolve", .pass);

    // --- frontend tour: one rich realistic file lexes + parses ---------------
    const t_tour = b.addRunArtifact(mrustc_exe);
    t_tour.setEnvironmentVariable("MRUSTC_TARGET_VER", mrustc_target_ver);
    t_tour.addFileArg(b.path("examples/01-frontend-tour/tour.rs"));
    t_tour.addArgs(&.{ "-Z", "stop-after=parse" });
    t_tour.expectExitCode(0);
    test_step.dependOn(&t_tour.step);

    // --- the four Rust editions all parse ------------------------------------
    const edition_src = b.addWriteFiles().add("edition.rs",
        \\fn main() { let _x: u32 = 1 + 2; }
        \\
    );
    for ([_][]const u8{ "2015", "2018", "2021", "2024" }) |ed| {
        const t_ed = b.addRunArtifact(mrustc_exe);
        t_ed.setEnvironmentVariable("MRUSTC_TARGET_VER", mrustc_target_ver);
        t_ed.addFileArg(edition_src);
        t_ed.addArgs(&.{ "--edition", ed, "-Z", "stop-after=parse" });
        t_ed.expectExitCode(0);
        test_step.dependOn(&t_ed.step);
    }

    if (minicargo_exe) |exe| {
        // minicargo links common_lib and prints its cargo-package usage.
        // (A full `-n` dry-run additionally spawns mrustc for cfg detection,
        // which needs the two binaries co-located -- exercised via `zig build`
        // + `minicargo`, not in this hermetic unit test.)
        const t_mc = b.addRunArtifact(exe);
        t_mc.addArg("--help");
        t_mc.expectExitCode(0);
        t_mc.expectStdOutMatch("minicargo");
        t_mc.expectStdOutMatch("Cargo.toml");
        test_step.dependOn(&t_mc.step);
    }

    // All build-graph (no shell): mrustc compiles the .rs with `zig-cc` as $CC,
    // then a second Run executes the produced binary and checks its exit term.
    // docs/06-libcore.md.
    if (target.query.isNative()) {
        const app = mrustcCompile(b, mrustc_exe, zigcc, b.path("examples/02-mini-core-runnable/mini_core.rs"), null);
        runExpect(b, test_step, app, 14);
    }

    // --- `zig build demo`: run the mini-core use-cases (mrustc -> C -> zig cc) -
    const demo_step = b.step("demo", "Build + run the mini-core examples (mrustc -> C -> zig cc)");
    if (target.query.isNative()) {
        // (a) self-contained mini libcore: 2 + 3*4 -> exit 14.
        const a = mrustcCompile(b, mrustc_exe, zigcc, b.path("examples/02-mini-core-runnable/mini_core.rs"), null);
        runExpect(b, demo_step, a, 14);
        const kernel = b.addObject(.{
            .name = "kernel",
            .root_module = b.createModule(.{
                .target = b.graph.host,
                .optimize = .ReleaseFast,
                .root_source_file = b.path("examples/02-mini-core-runnable/kernel.zig"),
            }),
        });
        const f = mrustcCompile(b, mrustc_exe, zigcc, b.path("examples/02-mini-core-runnable/ffi.rs"), .{ .extra_obj = kernel.getEmittedBin() });
        runExpect(b, demo_step, f, 42);
    }

    // --- `zig build -Dlibcore -Drustc-src=<dir> libcore`: build OFFICIAL libcore
    // Opt-in. Drives minicargo (with `zig cc` as $CC) to build the real libcore
    // from a rustc source tree, then compiles + runs a #![no_std] program against
    // it (use_real_core.rs -> exit 14). All build-graph, no shell. docs/06.
    //
    // The source is a LOCAL path, not a zon dependency: zig's package fetcher
    // cannot unpack `rustc-1.74.0-src.tar.gz` from static.rust-lang.org
    // (`error: ... TarHeader` -- its HTTP client chokes on that CDN, though curl
    // is fine). So fetch it yourself and point `-Drustc-src` at the extracted
    // `rustc-1.74.0-src/` (docs/06 §"Getting the source").
    if (b.option(bool, "libcore", "Bootstrap the official libcore via minicargo (needs -Drustc-src)") orelse false) {
        const rustc_src = b.option([]const u8, "rustc-src", "Path to an extracted rustc-1.74.0-src/ tree (for -Dlibcore)");
        if (minicargo_exe) |mc| {
            if (rustc_src == null) {
                std.log.warn("-Dlibcore needs -Drustc-src=<dir> (an extracted rustc-1.74.0-src/); " ++
                    "curl https://static.rust-lang.org/dist/rustc-1.74.0-src.tar.gz | tar xz  (docs/06)", .{});
            } else {
                const src = rustc_src.?;
                const lc_step = b.step("libcore", "Bootstrap libcore from -Drustc-src");

                // Same zig-cc launcher indirection as mrustcCompile: minicargo
                // reads $CC and $MRUSTC_PATH from the environment, which the maker
                // resolves into KEY=VALUE argv pairs before the `--` separator.
                const mc_run = b.addRunArtifact(zigcc);
                mc_run.addArg("--mrustc-run");
                mc_run.setEnvironmentVariable("MRUSTC_TARGET_VER", mrustc_target_ver);
                mc_run.addPrefixedArtifactArg("CC=", zigcc);
                mc_run.addPrefixedArtifactArg("MRUSTC_PATH=", mrustc_exe);
                mc_run.addArg("--");
                mc_run.addArtifactArg(mc);
                mc_run.addArg(b.pathJoin(&.{ src, "library/core" }));
                mc_run.addArg("--script-overrides");
                mc_run.addDirectoryArg(mrustc.path("script-overrides/stable-1.74.0-linux"));
                mc_run.addArg("--output-dir");
                const outdir = mc_run.addOutputDirectoryArg("libcore-out");
                mc_run.expectExitCode(0);

                // Install the built libcore into zig-out/lib/libcore-out so it is
                // reachable at a stable path (`mrustc -L zig-out/lib/libcore-out`)
                // instead of the content-hashed .zig-cache/o/<hash>/ location.
                const lc_install = b.addInstallDirectory(.{
                    .source_dir = outdir,
                    .install_dir = .lib,
                    .install_subdir = "libcore-out",
                    .exclude_extensions = &[_][]const u8{
                        "d",
                        "txt",
                        "c",
                    },
                });
                lc_step.dependOn(&lc_install.step);

                // compile + run a no_std program against the freshly-built core.
                const urc = b.addRunArtifact(zigcc);
                urc.addArg("--mrustc-run");
                urc.setEnvironmentVariable("MRUSTC_TARGET_VER", mrustc_target_ver);
                urc.addPrefixedArtifactArg("CC=", zigcc);
                urc.addArg("--");
                urc.addArtifactArg(mrustc_exe);
                urc.addFileArg(b.path("examples/02-mini-core-runnable/use_real_core.rs"));
                urc.addArg("-L");
                urc.addDirectoryArg(outdir);
                urc.addArgs(&.{ "--crate-type", "bin", "-o" });
                const app = urc.addOutputFileArg("use_real_core");
                urc.expectExitCode(0);
                runExpect(b, lc_step, app, 14);
            }
        }
    }
}

fn buildZigCxxWrapper(
    b: *std.Build,
    opt: std.builtin.OptimizeMode,
    cross_triple: ?[]const u8,
) *std.Build.Step.Compile {
    const opts = b.addOptions();
    opts.addOption([]const u8, "zig_exe", b.graph.zig_exe);
    opts.addOption(?[]const u8, "triple", cross_triple);

    const mod = b.createModule(.{
        .target = b.graph.host,
        .optimize = opt,
        .root_source_file = b.path("tools/zigcc.zig"),
    });
    mod.addOptions("build_options", opts);
    const exe = b.addExecutable(.{
        .name = "zig-cc",
        .root_module = mod,
    });
    return exe;
}

/// Compile a `.rs` to a native binary with mrustc, using the `zig-cc` launcher
/// as `$CC`. Returns the produced binary as a LazyPath. Pure build-graph.
///
/// mrustc reads its C compiler from the `$CC` environment variable, but a Run
/// step's environment must be plain strings while the launcher path is a
/// build-output LazyPath (no getInstallPath/getPath in this toolchain). So we run
/// zig-cc itself in its cross-platform "--mrustc-run" launcher mode: the maker
/// resolves the artifact paths into `KEY=VALUE` argv pairs, and the launcher
/// exports them (CC, ZIGCC_EXTRA) before exec'ing mrustc. mrustc then invokes the
/// same zig-cc as `$CC` (without the sentinel) for the actual compile/link.
fn mrustcCompile(
    b: *std.Build,
    mrustc_exe: *std.Build.Step.Compile,
    zigcc: *std.Build.Step.Compile,
    src: std.Build.LazyPath,
    opts: ?struct { extra_obj: std.Build.LazyPath },
) std.Build.LazyPath {
    const cg = b.addRunArtifact(zigcc);
    cg.addArg("--mrustc-run");
    cg.setEnvironmentVariable("MRUSTC_TARGET_VER", mrustc_target_ver);
    cg.addPrefixedArtifactArg("CC=", zigcc); // zig-cc compiles mrustc's emitted C
    if (opts) |o| {
        cg.addPrefixedFileArg("ZIGCC_EXTRA=", o.extra_obj); // link a Zig object
    }
    cg.addArg("--");
    cg.addArtifactArg(mrustc_exe);
    cg.addFileArg(src);
    cg.addArg("-o");
    const app = cg.addOutputFileArg("app");
    cg.expectExitCode(0);
    return app;
}

/// Add a step that runs `app` and asserts it exits with `code`.
fn runExpect(b: *std.Build, parent: *std.Build.Step, app: std.Build.LazyPath, code: u8) void {
    const r = std.Build.Step.Run.create(b, "run produced binary");
    r.addFileArg(app);
    r.addCheck(.{ .expect_term = .{ .exited = code } });
    parent.dependOn(&r.step);
}

/// Add one Run step per fixture in `paths`, driving mrustc up to `stage`
/// (`-Z stop-after=<stage>`).
///
/// `.pass` cases assert a clean exit (0). `.fail` cases (deliberately broken
/// Rust) expect mrustc to *abort*: it raises compile errors via `abort()`
/// (src/span.cpp) -> SIGABRT, not a tidy non-zero return. The Run step's term
/// check accepts that directly (`expect_term = .{ .signal = 6 }`), so the step
/// passes exactly when mrustc dies on the bad input -- no shell needed.
fn addStageTests(
    b: *std.Build,
    test_step: *std.Build.Step,
    exe: *std.Build.Step.Compile,
    expect_fail: *std.Build.Step.Compile,
    paths: []const []const u8,
    stage: []const u8,
    expect: enum { pass, fail },
) void {
    const stage_arg = b.fmt("stop-after={s}", .{stage});
    for (paths) |rel| {
        switch (expect) {
            .pass => {
                const run = b.addRunArtifact(exe);
                run.setEnvironmentVariable("MRUSTC_TARGET_VER", mrustc_target_ver);
                run.addFileArg(b.path(rel));
                run.addArgs(&.{ "-Z", stage_arg });
                run.expectExitCode(0);
                test_step.dependOn(&run.step);
            },
            // mrustc under `expect-fail`: the step passes iff mrustc *rejects*
            // the bad input (any non-zero exit or signal -- portable, no shell).
            .fail => {
                const run = b.addRunArtifact(expect_fail);
                run.setEnvironmentVariable("MRUSTC_TARGET_VER", mrustc_target_ver);
                run.addArtifactArg(exe); // argv[1] = mrustc
                run.addFileArg(b.path(rel));
                run.addArgs(&.{ "-Z", stage_arg });
                run.expectExitCode(0); // expect-fail returns 0 when mrustc failed
                test_step.dependOn(&run.step);
            },
        }
    }
}

/// A C++14 module configured the way every mrustc target wants it: native libc
/// + libc++, no RTTI/exceptions tweaks needed beyond the upstream defaults.
fn cxxModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    return b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libcpp = true,
        // mrustc relies on patterns UBSan flags as UB (e.g. binding a reference
        // to a transiently-null GenericParams* in hir_typeck/static.cpp). These
        // are benign upstream (gcc/clang without -fsanitize), but zig defaults
        // sanitize_c to .full in Debug/ReleaseSafe and traps. Match the upstream
        // Makefile and build the C++ sources without the C sanitizers.
        .sanitize_c = .off,
    });
}

/// Common C++ compile flags, mirroring the upstream Makefile. Nothing is
/// promoted to -Werror: mrustc targets gcc 5/6 and zig's newer clang emits
/// extra (harmless) diagnostics.
const cxx_flags = [_][]const u8{
    "-std=c++14",
    "-Wall",
    "-Wno-pessimizing-move",
    "-Wno-misleading-indentation",
    "-Wno-unused-variable",
    "-Wno-unused-private-field",
    "-Wno-deprecated-declarations",
};

fn addCxxSources(m: *std.Build.Module, root: std.Build.LazyPath, files: []const []const u8) void {
    m.addCSourceFiles(.{
        .root = root,
        .files = files,
        .flags = &cxx_flags,
        .language = .cpp,
    });
}

/// Inject the build metadata that `src/version.cpp` expects via -D defines.
fn stampVersion(m: *std.Build.Module) void {
    const q = "\""; // wrap string macros in literal quotes for the C preprocessor
    m.addCMacro("VERSION_GIT_ISDIRTY", "0");
    m.addCMacro("VERSION_GIT_FULLHASH", q ++ mrustc_rev ++ q);
    m.addCMacro("VERSION_GIT_SHORTHASH", q ++ mrustc_rev[0..8] ++ q);
    m.addCMacro("VERSION_GIT_BRANCH", q ++ "master" ++ q);
    m.addCMacro("VERSION_BUILDTIME", q ++ "mrust-zig" ++ q);
}

// src/*.cpp object list, transcribed from the upstream Makefile `OBJ` set.
const mrustc_srcs = [_][]const u8{
    "main.cpp",
    "version.cpp", // build metadata injected via stampVersion()/addCMacro
    "span.cpp",
    "rc_string.cpp",
    "debug.cpp",
    "ident.cpp",
    "ast/ast.cpp",
    "ast/types.cpp",
    "ast/crate.cpp",
    "ast/path.cpp",
    "ast/expr.cpp",
    "ast/pattern.cpp",
    "ast/dump.cpp",
    "parse/parseerror.cpp",
    "parse/token.cpp",
    "parse/tokentree.cpp",
    "parse/interpolated_fragment.cpp",
    "parse/tokenstream.cpp",
    "parse/lex.cpp",
    "parse/ttstream.cpp",
    "parse/root.cpp",
    "parse/paths.cpp",
    "parse/types.cpp",
    "parse/expr.cpp",
    "parse/pattern.cpp",
    "expand/mod.cpp",
    "expand/macro_rules.cpp",
    "expand/cfg.cpp",
    "expand/format_args.cpp",
    "expand/asm.cpp",
    "expand/concat.cpp",
    "expand/stringify.cpp",
    "expand/file_line.cpp",
    "expand/derive.cpp",
    "expand/lang_item.cpp",
    "expand/std_prelude.cpp",
    "expand/crate_tags.cpp",
    "expand/include.cpp",
    "expand/env.cpp",
    "expand/test.cpp",
    "expand/rustc_diagnostics.cpp",
    "expand/proc_macro.cpp",
    "expand/assert.cpp",
    "expand/compile_error.cpp",
    "expand/codegen.cpp",
    "expand/doc.cpp",
    "expand/lints.cpp",
    "expand/misc_attrs.cpp",
    "expand/stability.cpp",
    "expand/panic.cpp",
    "expand/rustc_box.cpp",
    "expand/test_harness.cpp",
    "macro_rules/mod.cpp",
    "macro_rules/eval.cpp",
    "macro_rules/parse.cpp",
    "resolve/use.cpp",
    "resolve/index.cpp",
    "resolve/absolute.cpp",
    "resolve/common.cpp",
    "hir/from_ast.cpp",
    "hir/from_ast_expr.cpp",
    "hir/dump.cpp",
    "hir/hir.cpp",
    "hir/hir_ops.cpp",
    "hir/generic_params.cpp",
    "hir/crate_ptr.cpp",
    "hir/expr_ptr.cpp",
    "hir/type.cpp",
    "hir/path.cpp",
    "hir/expr.cpp",
    "hir/pattern.cpp",
    "hir/visitor.cpp",
    "hir/crate_post_load.cpp",
    "hir/inherent_cache.cpp",
    "hir_conv/expand_type.cpp",
    "hir_conv/constant_evaluation.cpp",
    "hir_conv/resolve_ufcs.cpp",
    "hir_conv/bind.cpp",
    "hir_conv/markings.cpp",
    "hir_conv/lifetime_elision.cpp",
    "hir_typeck/outer.cpp",
    "hir_typeck/common.cpp",
    "hir_typeck/helpers.cpp",
    "hir_typeck/static.cpp",
    "hir_typeck/impl_ref.cpp",
    "hir_typeck/resolve_common.cpp",
    "hir_typeck/expr_visit.cpp",
    "hir_typeck/expr_cs.cpp",
    "hir_typeck/expr_cs__enum.cpp",
    "hir_typeck/expr_check.cpp",
    "hir_expand/annotate_value_usage.cpp",
    "hir_expand/closures.cpp",
    "hir_expand/ufcs_everything.cpp",
    "hir_expand/reborrow.cpp",
    "hir_expand/erased_types.cpp",
    "hir_expand/vtable.cpp",
    "hir_expand/static_borrow_constants.cpp",
    "hir_expand/lifetime_infer.cpp",
    "mir/mir.cpp",
    "mir/mir_ptr.cpp",
    "mir/dump.cpp",
    "mir/helpers.cpp",
    "mir/visit_crate_mir.cpp",
    "mir/from_hir.cpp",
    "mir/from_hir_match.cpp",
    "mir/mir_builder.cpp",
    "mir/check.cpp",
    "mir/cleanup.cpp",
    "mir/optimise.cpp",
    "mir/check_full.cpp",
    "mir/borrow_check.cpp",
    "hir/serialise.cpp",
    "hir/deserialise.cpp",
    "hir/serialise_lowlevel.cpp",
    "trans/trans_list.cpp",
    "trans/mangling_v2.cpp",
    "trans/enumerate.cpp",
    "trans/auto_impls.cpp",
    "trans/monomorphise.cpp",
    "trans/codegen.cpp",
    "trans/codegen_c.cpp",
    "trans/codegen_c_structured.cpp",
    "trans/codegen_mmir.cpp",
    "trans/target.cpp",
    "trans/allocator.cpp",
};

// tools/minicargo/*.cpp object list, from tools/minicargo/Makefile.
const minicargo_srcs = [_][]const u8{
    "main.cpp",
    "manifest.cpp",
    "repository.cpp",
    "cfg.cpp",
    "build.cpp",
    "jobs.cpp",
    "file_timestamp.cpp",
    "os.cpp",
    "resolve_0minicargo.cpp",
    "resolve_cargo.cpp",
};
