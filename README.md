# 事前にやる必要があること

- ECRレポジトリの作成とイメージのPUSH
  - terraform apply時にvariablesとしてイメージのURIを渡すので控えておく

# terraform apply時に渡すvariables

- account_id : 利用するAWSアカウントID
- project_name : AWSリソース名の名前に付与される文字列 リソース名は"[project_name]-[env]-リソース識別子"
- env : AWSリソース名の名前に付与される文字列
- aws_region : リソースを作成する対象のリージョン
- image_uri : ECRにPUSHしたイメージのURI
