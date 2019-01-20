/*!
 *
 * @file    AC_STUB.h
 *
 * @brief   汎用スタブ基底クラスのヘッダ定義を記述する。
 *
 * @par     備考
 * @details
 *        - 既に存在するライブラリのメソッドをフックして別のことを行わせる。
 *        - inlineのメソッドやtemplateメソッドはフックできないことがある。
 *        - 本体はCreateStubスクリプト(perl)で生成する。
 *
 * COPYRIGHT(c) 2018. MITSUBISHI ELECTRIC CORPORATION ALL RIGHTS RESERVED.
 */

#ifndef __HOOK_AC_STUB_H__
#define __HOOK_AC_STUB_H__

//---- ヘッダファイルインクルード
#include <string>
#include <vector>
#include <map>

//---- 定数定義

// スタブ発火箇所の定義
const int IGNITION_NONE   = 0;  //!< なし
const int IGNITION_BEFORE = 1;  //!< メソッド開始直後
const int IGNITION_AFTER  = 2;  //!< メソッド終了直前
const int IGNITION_BOTH   = IGNITION_BEFORE | IGNITION_AFTER;
                                //!< メソッド開始直後と終了直前の両方
const int IGNITION_NO_ORG = 65536;
                                //!< オリジナルメソッドを実行しない

//---- 名前空間定義
/*!
 * @namespace   HOOK
 * @brief       汎用フックスタブ
 */
namespace HOOK
{

/*!
 *
 * @class   HOOK::AC_STUB AC_STUB.h “inc/AC_STUB.h”
 *
 * @b       クラス論理名
 *
 *          汎用スタブクラス
 *
 * @brief   既に存在するライブラリのメソッドをフックして別のことを行わせるための
 *          汎用スタブクラスの基底クラスの実装内容を記述する。
 *
 * @par     概要説明
 *
 * @details
 *        - 既に存在するライブラリのメソッドをフックして別のことを行わせるための
 *          以下の処理を
 *          ライブラリアドレス取得、メソッドアドレス取得処理
 *        - 出発機通過予定機一覧情報を初期化したのち、注意喚起情報メンテナンス、
 *          通過予定機抽出、通過済先行機抽出、出発機情報ソートを行う。
 *
 * @par     備考
 *          なし
 *
 */
class AC_STUB {
public:
    typedef struct T_HOOK {
        const char* library;
        const char* demangle;
        const char* method;

        T_HOOK( const char* library = "",
                const char* demangle = "",
                const char* method = "") :
            library(library), demangle(demangle), method(method) { }
    } T_so_func_pair;

    typedef ::std::vector<T_HOOK> T_hook_list;


    static bool   debug;            // デバックフラグ

    bool          trace;            // トレースフラグ
    int           execute;          // 発火箇所
    unsigned long count;            // メソッド呼び出しカウンタ
    unsigned long ignition;         // 発火条件
    std::string   data;             // スタブ情報

    const std::string method;       // メソッド文字列
    const std::string library;      // ライブラリ文字列

private:
    // soライブラリのアドレスポインタ型の別名定義
    typedef void* T_so_ptr;
    // メソッドのアドレスポインタ型の別名定義
    typedef const void* T_func_ptr;

    // soライブラリ名型の別名定義
    typedef const ::std::string T_so;
    // メソッドシンボル名型の別名定義
    typedef const ::std::string T_func;

    // soライブラリリスト(map)の別名定義
    typedef ::std::map<T_so,   T_so_ptr>   T_so_map;
    // メソッドリスト(map)の別名定義
    typedef ::std::map<T_func, T_func_ptr> T_func_map;

    // スタブオブジェクトリスト
    static std::vector<AC_STUB*> stub_list;

    // soライブラリリスト
    static T_so_map   so_map;

    // メソッドリスト
    T_func_map func_map;
protected:
    AC_STUB(                        // 構築子
            const T_hook_list& in); // [in] ライブラリと関数の紐付けリスト

public:
    virtual ~AC_STUB();             // 消滅子

    T_func_ptr getFunc(             // メソッドアドレス取得
            T_func str);            // [in] メソッドシンボル

    void setIgnition(               // スタブ発火条件設定
            unsigned long ignition = 1,
                                    // [in] 発火条件
            int execute = IGNITION_BEFORE,
                                    // [in] 発火箇所
            std::string data = "",  // [in] スタブ情報
            bool trace = false);    // [in] トレースON/OFFフラグ

    void clear();                   // スタブ発火条件初期化

    static void ClearAll();         // スタブ発火条件全初期化

    void InLog(                     // メソッド開始ログ表示
            const char* id = NULL,  // [in] フックメソッドのID(省略可能)
            const char* msg = NULL); // [in] フックメソッドからの情報(省略可能)

    void OutLog(                    // メソッド終了ログ表示
            const char* id = NULL,  // [in] フックメソッドのID(省略可能)
            const char* msg = NULL); // [in] フックメソッドからの情報(省略可能)

    bool IgnitionJudgment(          // スタブ実行/否実行判定
            int execute,            // [in] 発火箇所
            const char* id = NULL); // [in] フックメソッドのID(省略可能)

private:

    void LibraryMethodMapping(      // ライブラリ-メソッドマッピング処理
            const T_hook_list& in); // [in] ライブラリと関数の紐付けリスト

    void MappingClear();            // ライブラリマッピングクリア処理

    const std::string CreateLiblary( // ライブラリ文字列生成
            const T_hook_list& in); // [in] ライブラリと関数の紐付けリスト

    const std::string CreateMethod( // メソッド文字列生成
            const T_hook_list& in); // [in] ライブラリと関数の紐付けリスト

    void LogOut();                  // ログ表示

    __attribute__((constructor))
    static void Start();            // スタブフック開始処理

    __attribute__((destructor))
    static void End();              // スタブフック終了処理
};

} // end namespace HOOK

#endif // __HOOK_AC_STUB_H__
