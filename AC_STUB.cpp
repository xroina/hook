/*!
 * @file    AC_STUB.cpp
 *
 * @brief   汎用スタブ基底クラスの実装内容を記述する。
 *
 * @par     備考
 * @details
 *        - 既に存在するライブラリのメソッドをフックして別のことを行わせる。
 *        - inlineのメソッドやtemplateメソッドはフックできないことがある。
 *        - 本体はCreateStubスクリプト(perl)で生成する。
 *
 */

//---- ヘッダファイルインクルード
#include "AC_STUB.h"                    // 汎用スタブクラス

#include <cstdarg>
#include <dlfcn.h>
#include <iostream>
#include <sstream>
#include <set>

//---- 名前空間定義
/*!
 * @namespace   HOOK
 * @brief       汎用フックスタブ
 */
namespace HOOK
{

// 他クラス定義
using ::std::cout;
using ::std::cerr;
using ::std::endl;
using ::std::string;
using ::std::stringstream;
using ::std::vector;
using ::std::set;

//! デバックフラグ
bool AC_STUB::debug = false;

//! スタブオブジェクトリスト
vector<AC_STUB*> AC_STUB::stub_list     __attribute__((init_priority(101)));

//! soライブラリリスト
AC_STUB::T_so_map   AC_STUB::so_map     __attribute__((init_priority(101)));

/*!
 * @b       メンバ関数名
 *          構築子
 *
 * @brief   クラス生成に伴う初期化処理。
 *
 * @par     機能説明
 * @details
 *        - ライブラリと関数の紐付けリストをパラメータとして、フックに必要な初期化処理を行う。
 *        - スタブオブジェクトをリストに登録する。
 *
 * @param   [in]    in              ライブラリと関数の紐付けリスト
 *
 * @return  なし
 *
 * @par     備考
 *          なし
 */
AC_STUB::AC_STUB(
        const T_hook_list& in) :    // [in] ライブラリと関数の紐付けリスト
        trace(false), execute(IGNITION_NONE),
        count(0), ignition(0), data(""),
        method(CreateLiblary(in)), library(CreateMethod(in)),
        func_map()
{
//    Dl_info info;
//    dladdr(__builtin_return_address(0), &info);
//
//    cout << "[" << __func__ << "] " <<
//            "return => " << __builtin_return_address(0) << ", " <<
//            "this => "   << this << ", " <<
//            "sname => "  << info.dli_sname << ", " <<
//            "saddr => "  << info.dli_saddr << ", " <<
//            "fbase=> "   << info.dli_fbase << ", " <<
//            "fname => "  << info.dli_fname << endl;
    stub_list.push_back(this);

    LibraryMethodMapping(in);
}

/*!
 * @b       メンバ関数名
 *          消滅子
 *
 * @brief   クラス消滅に伴う終了処理。
 *
 * @par     機能説明
 * @details
 *        - フックで利用した情報を開放する。
 *
 * @param   なし
 * @return  なし
 *
 * @par     備考
 *          なし
 */
AC_STUB::~AC_STUB()
{
    MappingClear();
}

/*!
 * @b       メンバ関数名
 *          ライブラリ文字列生成
 *
 * @brief   ライブラリと関数の紐付けリストからライブラリ文字列を構成する。
 *
 * @par     機能説明
 * @details
 *        - ライブラリと関数の紐付けリストからライブラリ文字列を構成する。
 *
 * @param   [in]    in              ライブラリと関数の紐付けリスト
 *
 * @return  ライブラリ文字列
 *
 * @par     備考
 *          なし
 */
const string AC_STUB::CreateLiblary(const T_hook_list& in)
{
    set<string> set;
    for(auto i = in.begin(); i != in.end(); i++)
        set.insert(i->library);

    stringstream library;
    for(auto i = set.begin(); i != set.end(); ++i) {
        if(i != set.begin()) library << ", ";
        library << *i;
    }
    return library.str();
}

/*!
 * @b       メンバ関数名
 *          メソッド文字列生成
 *
 * @brief   ライブラリと関数の紐付けリストからメソッド文字列を構成する。
 *
 * @par     機能説明
 * @details
 *        - ライブラリと関数の紐付けリストからメソッド文字列を構成する。
 *        - 関数名がない場合、シンボル情報で文字列を構成する。
 *
 * @param   [out]   in              ライブラリと関数の紐付けリスト
 *
 * @return  メソッド文字列
 *
 * @par     備考
 *          なし
 */
const string AC_STUB::CreateMethod(const T_hook_list& in)
{
    set<string> set;
    for(auto i = in.begin(); i != in.end(); i++)
    {
        if(i->method && i->method[0]) {
            set.insert(i->method);
        } else {
            set.insert(i->demangle);
        }
    }

    stringstream method;
    for(auto i = set.begin(); i != set.end(); ++i) {
        if(i != set.begin()) method << ", ";
        method << *i;
    }
    return method.str();
}

/*!
 * @b       メンバ関数名
 *          ライブラリ-メソッドマッピング処理
 *
 * @brief   ライブラリアドレス-メソッドアドレスマッピング処理。
 *
 * @par     機能説明
 * @details
 *        - ライブラリと関数の紐付けリストをパラメータとして、フックに必要な情報を取得し、
 *          soライブラリマップ、メソッドマップを構成する。
 *        - soライブラリをdlopenにて開き、アドレスを取得し、soライブラリマップに登録する。
 *            - 取得に失敗した場合はTestを異常終了する。
 *        - dlopenにてリンクされたsoライブラリのアドレスと、メソッドシンボルから
 *          メソッドが配置されているアドレスをdlsymにて取得し、メソッドマップに登録する。
 *            - 取得に失敗した場合はTestを異常終了する。
 *
 * @param   [out]   in              ライブラリと関数の紐付けリスト
 *
 * @return  なし
 *
 * @par     備考
 *          なし
 */
void AC_STUB::LibraryMethodMapping(const T_hook_list& in)
{
    cout << "[+] HOOK" << endl;

    char* err = dlerror(); // flash dlerror

    for(auto i = in.begin(); i != in.end(); i++) {
        T_so_ptr pso = NULL;


        if(so_map.find(i->library) == so_map.end()) {
            cout << "  [+] dlopen(" << i->library << ")";

            pso = dlopen(i->library, RTLD_NOW);

            cout << " -> " << pso << endl;

            err = dlerror();
            if(NULL == pso || NULL != err) {
                cerr << "  [+] dlerror() -> " << err <<endl;
                exit(EXIT_FAILURE);
            }

            so_map[i->library] = pso;
        } else {
            pso = so_map[i->library];
        }

        cout << "    [+] dlsym(" << i->library << ", " <<
                i->method << "[" << i->demangle << "])";

        T_func_ptr pfunc = dlsym(pso, i->demangle);

        cout << " -> " << pfunc << endl;

        err = dlerror();
        if(NULL == pfunc || NULL != err) {
            cerr << "  [+] dlerror() ->" << err <<endl;
            exit(EXIT_FAILURE);
        }

        func_map[i->demangle] = pfunc;

//        while(1) {
//            cout << "    [+] dlsym(next, " << i->method << ")";
//
//            T_func_ptr p = dlsym(RTLD_NEXT, i->demangle);
//
//            cout << " -> " << p << endl;
//
//            err = dlerror();
//            if(NULL != err) {
//                cerr << "  [+] dlerror() -> " << err <<endl;
//                exit(EXIT_FAILURE);
//            }
//
//            if(p == NULL || p == pfunc) break;
//
//            pfunc = p;
//        }
    }
}

/*!
 * @b       メンバ関数名
 *          ライブラリマッピングクリア処理
 *
 * @brief   ライブラリ-メソッドマッピング処理により生成された情報を開放する。
 *
 * @par     機能説明
 * @details
 *        - soライブラリマップ、メソッドマップを開放する。
 *        - soライブラリマップにあるsoライブラリのアドレスをdlcloseにより閉じる。
 *        - 登録されているアドレスを全て閉じたら、soライブラリマップをクリアする。
 *            - 開放に失敗してもエラーを出力するだけで何もしない。
 *
 * @param   なし
 * @return  なし
 *
 * @par     備考
 *          なし
 */
void AC_STUB::MappingClear()
{
    if(so_map.empty()) return;

    cout << "[+] UNHOOK" << endl;

    char* err = dlerror(); // flash dlerror

    for(auto i = so_map.begin(); i != so_map.end(); i++) {
        T_so_ptr pso = i->second;

        if(NULL == pso) continue;

        int ret = dlclose(pso);

        cout << "  [+] library:" << i->first << endl;
        cout << "    [+] dlclose(" << pso << ") -> " << ret << endl;

        err = dlerror();
        if(ret != 0 || NULL != err) {
            cerr << "  [+] dlerror() -> " << err <<endl;
        }

        i->second = NULL;
    }
    so_map.clear();
}

/*!
 * @b       メンバ関数名
 *          メソッドアドレス取得
 *
 * @brief   メソッドマップより、メソッドのアドレスを取得する。
 *
 * @par     機能説明
 * @details
 *        - メソッドマップより、メソッドのアドレスを取得する。
 *
 * @param   [in]    str              メソッドシンボル
 *
 * @return  メソッドのアドレスポインタ
 *
 * @par     備考
 *          なし
 */
AC_STUB::T_func_ptr AC_STUB::getFunc(
        T_func str)             // [in] メソッドシンボル
{
    return func_map[str];
}

/*!
 * @b       メンバ関数名
 *          スタブ発火条件設定
 *
 * @brief   スタブを動かす条件を設定する。
 *
 * @par     機能説明
 * @details
 *        - 実際にスタブを動かす条件を設定する。
 *        - スタブオブジェクトが持つ以下の情報を設定する。
 *            - メソッド呼び出しカウンタを0にする。
 *            - 発火箇所を設定する。省略された場合は、メソッド開始直後。
 *              メソッド開始直後、メソッド終了直前が指定できる。
 *                  メソッド開始直後 :  IGNITION_BEFORE
 *                  メソッド終了直前 :  IGNITION_AFTER
 *                  両方          :  IGNITION_BOTH
 *                  オリジナルメソッドを実行しない :
 *                                  IGNITION_NO_ORG
 *                      それぞれor条件(|)で指定できる。
 *            - 発火条件を設定する。省略された場合は1。
 *              呼び出しカウンタが、発火条件と一致した場合、スタブが発火する。
 *            - スタブ情報を設定する。省略された場合はヌル文字("")
 *              フックした関数内で何か他のことをやらせたいなど、汎用的に利用する。
 *            - 対象メソッドのIN/OUTを標準出力するフラグを設定する。
 *              trueを設定するとフック対象のメソッド開始直後と終了直前に
 *              標準出力へスタブ発火条件を出力する。
 *
 * @param   [in]    ignition            発火条件(省略可能)
 * @param   [in]    execute             発火箇所(省略可能)
 * @param   [in]    data                スタブ情報(省略可能)
 * @param   [in]    trace               トレースON/OFFフラグ(省略可能)
 *
 * @return  なし
 *
 * @par     備考
 *          なし
 */
void AC_STUB::setIgnition(
        unsigned long ignition, // [in] 発火条件
        int execute,            // [in] 発火箇所
        string data,            // [in] スタブ情報
        bool trace)             // [in] トレースON/OFFフラグ
{
    this->count = 0;
    this->execute = execute;
    this->ignition = ignition;
    this->data = data;
    this->trace = trace;
}

/*!
 * @b       メンバ関数名
 *          スタブ発火条件初期化
 *
 * @brief   スタブを動かす条件を初期化する。
 *
 * @par     機能説明
 * @details
 *        - 実際にスタブを動かす条件を初期化する。
 *        - スタブオブジェクトが持つ以下の情報を初期化する。
 *            - メソッド呼び出しカウンタを0にする。
 *            - 発火箇所をなしに設定する。
 *            - 発火条件を0に設定する。
 *            - スタブ情報をヌル文字("")に設定する。
 *            - 対象メソッドのIN/OUTを標準出力するフラグをOFFに設定する。
 *
 * @param   なし
 * @return  なし
 *
 * @par     備考
 *          なし
 */
void AC_STUB::clear() {
    count = 0;
    execute = IGNITION_NONE;
    ignition = 0;
    data = "";
    trace = false;
}

/*!
 * @b       メンバ関数名
 *          スタブ発火条件全初期化
 *
 * @brief   スタブを動かす条件を全て初期化する。
 *
 * @par     機能説明
 * @details
 *        - 実際にスタブを動かす条件を設定する。
 *        - 全てのスタブオブジェクトが持つ情報を初期化する。
 *        - デバックフラグをOFFにする。
 *
 * @param   なし
 * @return  なし
 *
 * @par     備考
 *          なし
 */
void AC_STUB::ClearAll() {
    for(auto i = stub_list.begin(); i != stub_list.end(); ++i)
    {
        (*i)->clear();
    }
    debug = false;
}

/*!
 * @b       メンバ関数名
 *          メソッド開始ログ表示
 *
 * @brief   メソッド開始ログを表示する。
 *
 * @par     機能説明
 * @details
 *        - デバックまたはトレースがONの場合、フックしたメソッドの開始ログを表示する。
 *        - 引数に指定したIDとメッセージ、メソッド情報を表示し、
 *          スタブオブジェクトが持つ以下の情報を表示する。
 *            - メソッド呼び出しカウンタ
 *            - 発火箇所
 *            - 発火条件
 *            - スタブ情報
 *        - ID,メッセージは省略可能
 *
 * @param   [in]    id          フックメソッドのID(省略可能)
 * @param   [in]    msg         フックメソッドからの情報(省略可能)
 *
 * @return  なし
 *
 * @par     備考
 *          なし
 */
void AC_STUB::InLog(
        const char * id,        // [in] フックメソッドのID(省略可能)
        const char* msg)        // [in] フックメソッドからの情報(省略可能)
{
    if(!debug && !trace) return;
    cout << "[+]HOOK ";
    if(id) cout << id << " ";
    cout << "Start:";
    LogOut();
    if(msg) cout << "  -> " << msg << endl;
}

/*!
 * @b       メンバ関数名
 *          メソッド終了ログ表示
 *
 * @brief   メソッド終了ログを表示する。
 *
 * @par     機能説明
 * @details
 *        - デバックまたはトレースがONの場合、フックしたメソッドの終了ログを表示する。
 *        - 引数に指定したIDとメッセージ、メソッド情報を表示し、
 *          スタブオブジェクトが持つ以下の情報を表示する。
 *            - メソッド呼び出しカウンタ
 *            - 発火箇所
 *            - 発火条件
 *            - スタブ情報
 *        - ID,メッセージは省略可能
 *
 * @param   [in]    id          フックメソッドのID(省略可能)
 * @param   [in]    msg         フックメソッドからの情報(省略可能)
 *
 * @return  なし
 *
 * @par     備考
 *          なし
 */
void AC_STUB::OutLog(
        const char * id,        // [in] フックメソッドのID(省略可能)
        const char* msg)        // [in] フックメソッドからの情報(省略可能)
{
    if(!debug && !trace) return;
    cout << "[+]HOOK ";
    if(id) cout << id << " ";
    cout << "Start:";
    LogOut();
    if(msg) cout << "  -> " << msg << endl;
}

/*!
 * @b       メンバ関数名
 *          スタブ実行/否実行判定
 *
 * @brief   スタブ処理を実行するかしないかを判定する。
 *
 * @par     機能説明
 * @details
 *        -
 *        - 引数に指定したIDとメッセージ、メソッド情報を表示し、
 *          スタブオブジェクトが持つ以下の情報を表示する。
 *            - メソッド呼び出しカウンタ
 *            - 発火箇所
 *            - 発火条件
 *            - スタブ情報
 *        - ID,メッセージは省略可能
 *
 * @param   [in]    execute     発火箇所
 * @param   [in]    id          フックメソッドのID(省略可能)
 *
 * @return  なし
 *
 * @par     備考
 *          なし
 */
bool AC_STUB::IgnitionJudgment(
        int execute,            // [in] 発火箇所
        const char* id)         // [in] フックメソッドのID(省略可能)
{
    if((this->execute & execute) == 0) return false;
    if(ignition != count) return false;
    cout << "    -> Ignition ";
    if(id) cout << id << " ";
    LogOut();
    return true;
}

/*!
 * @b       メンバ関数名
 *          ログ表示
 *
 * @brief   ログを表示する。
 *
 * @par     機能説明
 * @details
 *        - スタブオブジェクトが持つ以下の情報を表示する。
 *            - メソッド呼び出しカウンタ
 *            - 発火箇所
 *            - 発火条件
 *            - スタブ情報
 *
 * @param   なし
 * @return  なし
 *
 * @par     備考
 *          なし
 */
void AC_STUB::LogOut() {
    cout << method << " execute:"  << execute <<
            " ignition:" << ignition << " count:" << count <<
            " data:\"" << data << "\"" << endl;
}

#if DEBUG_DLOPEN
void*       p_dlopen_so = NULL;
const void* p_dlopen_func = NULL;
#endif

/*!
 * @b       メンバ関数名
 *          スタブフック開始処理
 *
 * @brief   スタブフック開始処理を記述する。
 *
 * @par     機能説明
 * @details
 *        - スタブフック開始処理を記述する。
 *
 * @param   なし
 * @return  なし
 *
 * @par     備考
 *          なし
 */
void AC_STUB::Start() {
    printf("[+] START HOOK STUB\n");
#if DEBUG_DLOPEN
    char* err = dlerror(); // flash dlerror
    p_dlopen_so = dlopen("/usr/lib64/libdl.so", RTLD_NOW);
    err = dlerror();
    if(NULL == p_dlopen_so || NULL != err) {
        printf("[+] dlopen error %s\n", err);
        p_dlopen_so = NULL;
        exit(EXIT_FAILURE);
        return;
    }
    p_dlopen_func = dlsym(p_dlopen_so, "dlopen");

    err = dlerror();
    if(NULL == p_dlopen_func || NULL != err) {
        printf("[+] dlsym error %s\n", err);
        exit(EXIT_FAILURE);
        return;
    }
#endif
}

/*!
 * @b       メンバ関数名
 *          スタブフック終了処理
 *
 * @brief   スタブフック終了処理を記述する。
 *
 * @par     機能説明
 * @details
 *        - スタブフック終了処理を記述する。
 *
 * @param   なし
 * @return  なし
 *
 * @par     備考
 *          なし
 */
void AC_STUB::End() {
    printf("[+] END HOOK STUB\n");
#if DEBUG_DLOPEN
    char* err = dlerror(); // flash dlerror

    if(NULL == p_dlopen_so) return;
    dlclose(p_dlopen_so);
    err = dlerror();
#endif
}

#if DEBUG_DLOPEN
void* dlopen (__const char *__file, int __mode) throw ()
{
    printf("    [+] load library:%s", __file);
    typedef void* (*F)(__const char *, int);
    F org = (F)p_dlopen_func;
    return (*org)(__file, __mode);
}
#endif

} // end namespace TEST
